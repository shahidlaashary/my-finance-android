#!/usr/bin/env python3
"""Validate/import the global card catalog and recheck official source pages.

Input import format: JSON array of records or {"records": [...]}.
No third-party dependencies. Never infers official artwork or auto-promotes trust.
"""
import argparse, hashlib, json, re, sys, urllib.error, urllib.request
from urllib.parse import urlparse
from datetime import datetime, timezone
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "assets/data/global_card_catalog.json"
REPORT = ROOT / "assets/data/card_verification_report.json"
ALLOWED = {"official_card_verified", "bank_branding_verified", "review_required", "unverified", "source_unreachable", "needs_source"}
HEX = re.compile(r"^#[0-9A-Fa-f]{6}$")

def now():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

def load_json(path, default):
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default

def normalize(record):
    required = ("countryCode", "institutionName", "institutionType", "officialWebsite")
    missing = [key for key in required if not str(record.get(key, "")).strip()]
    if missing: raise ValueError("Missing required fields: " + ", ".join(missing))
    code = str(record["countryCode"]).upper()
    if not re.fullmatch(r"[A-Z]{2}", code): raise ValueError("countryCode must be ISO alpha-2")
    for key in ("primaryColor", "secondaryColor", "accentColor"):
        value = record.get(key)
        if value and not HEX.fullmatch(value): raise ValueError(key + " must be #RRGGBB")
    for key in ("officialWebsite", "officialProductUrl", "officialImageUrl"):
        value = record.get(key)
        if value and not str(value).startswith("https://"): raise ValueError(key + " must use HTTPS")
    record["countryCode"] = code
    record.setdefault("aliases", [])
    # Imports cannot self-assert verification; only reviewed existing records retain it.
    record["verificationStatus"] = "unverified"
    record.setdefault("sourceUrl", record.get("officialProductUrl") or record["officialWebsite"])
    record.setdefault("lastCheckedAt", None)
    record.setdefault("sourceContentSha256", None)
    record.setdefault("imageContentSha256", None)
    record.setdefault("sourceChangedAt", None)
    record.setdefault("verificationEvidence", [])
    return record

def key(record):
    return (record["countryCode"], re.sub(r"[^a-z0-9]", "", record["institutionName"].lower()), str(record.get("cardType","")).lower(), str(record.get("cardNetwork","")).lower())

def import_records(catalog, paths):
    merged = {key(r): r for r in catalog["records"]}
    count = 0
    for filename in paths:
        raw = load_json(Path(filename), None)
        incoming = raw.get("records", []) if isinstance(raw, dict) else raw
        if not isinstance(incoming, list): raise ValueError(f"{filename}: expected a JSON array or records object")
        for item in incoming:
            r = normalize(dict(item))
            k = key(r)
            old = merged.get(k, {})
            # Preserve prior verification history only when the source URL is unchanged.
            if old.get("sourceUrl") == r.get("sourceUrl"):
                for field in ("verificationStatus","lastCheckedAt","sourceContentSha256","imageContentSha256","sourceChangedAt","verificationEvidence"):
                    r[field] = old.get(field, r.get(field))
            else:
                r["verificationStatus"] = "unverified"
                r["lastCheckedAt"] = None
                r["sourceContentSha256"] = None
                r["imageContentSha256"] = None
                r["sourceChangedAt"] = None
            merged[k] = r
            count += 1
    catalog["records"] = sorted(merged.values(), key=lambda x:(x["countryCode"],x["institutionName"].casefold(),str(x.get("cardType",""))))
    return count

def fetch_digest(url, limit):
    parsed = urlparse(url or '')
    if parsed.scheme != 'https' or not parsed.netloc:
        raise ValueError('Only absolute HTTPS URLs are allowed')
    req = urllib.request.Request(url, headers={'User-Agent':'MyFinance-CardCatalogVerifier/1.1'})
    with urllib.request.urlopen(req, timeout=25) as response:
        final = urlparse(response.geturl())
        if final.scheme != 'https': raise ValueError('Redirect left HTTPS')
        body = response.read(limit + 1)
        if len(body) > limit: raise ValueError('Source exceeds size limit')
        return response.status, hashlib.sha256(body).hexdigest(), response.geturl()

def check_sources(catalog):
    results=[]
    for r in catalog['records']:
        url = r.get('sourceUrl') or r.get('officialProductUrl') or r.get('officialWebsite')
        item={'countryCode':r['countryCode'],'institutionName':r['institutionName'],'sourceUrl':url}
        if not url:
            r['verificationStatus']='needs_source'; item['result']='needs_source'
        else:
            try:
                status,digest,final_url=fetch_digest(url,2000000)
                changed=bool(r.get('sourceContentSha256') and r['sourceContentSha256'] != digest)
                r['lastCheckedAt']=now(); r['sourceContentSha256']=digest
                item.update({'httpStatus':status,'finalUrl':final_url,'sourceSha256':digest,'sourceChanged':changed})
                if changed:
                    r['verificationStatus']='review_required'; r['sourceChangedAt']=r['lastCheckedAt']
                item['result']='source_changed_review_required' if changed else 'reachable'
            except (urllib.error.URLError,TimeoutError,ValueError) as exc:
                r['verificationStatus']='source_unreachable'; r['lastCheckedAt']=now()
                item.update({'result':'unreachable','error':str(exc)[:240]})
        image_url=r.get('officialImageUrl')
        if image_url:
            try:
                status,digest,final_url=fetch_digest(image_url,8000000)
                changed=bool(r.get('imageContentSha256') and r['imageContentSha256'] != digest)
                r['imageContentSha256']=digest
                item.update({'imageHttpStatus':status,'imageFinalUrl':final_url,'imageSha256':digest,'imageChanged':changed})
                if changed:
                    r['verificationStatus']='review_required'; r['sourceChangedAt']=now()
                    item['result']='card_art_changed_review_required'
            except (urllib.error.URLError,TimeoutError,ValueError) as exc:
                item.update({'imageResult':'unreachable_or_invalid','imageError':str(exc)[:240]})
                if r.get('verificationStatus') == 'official_card_verified': r['verificationStatus']='review_required'
        results.append(item)
    return results

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--import", dest="imports", action="append", default=[], help="JSON file to merge; repeatable")
    parser.add_argument("--check", action="store_true", help="recheck every official source URL")
    args=parser.parse_args()
    catalog=load_json(CATALOG, {"schemaVersion":1,"catalogId":"my-finance-global-card-catalog","updatedAt":None,"policy":{},"records":[]})
    imported=import_records(catalog,args.imports) if args.imports else 0
    results=check_sources(catalog) if args.check else []
    catalog["updatedAt"]=now()
    CATALOG.parent.mkdir(parents=True,exist_ok=True)
    CATALOG.write_text(json.dumps(catalog,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    if args.check:
        REPORT.write_text(json.dumps({"checkedAt":now(),"total":len(results),"sourceChanged":sum(1 for x in results if x.get("sourceChanged")),"imageChanged":sum(1 for x in results if x.get("imageChanged")),"results":results},ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"imported":imported,"totalRecords":len(catalog["records"]),"checked":len(results),"report":str(REPORT.relative_to(ROOT)) if args.check else None}))
if __name__=="__main__":
    try: main()
    except Exception as exc:
        print(f"catalog pipeline error: {exc}",file=sys.stderr); sys.exit(1)
