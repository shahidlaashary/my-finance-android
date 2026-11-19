import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "card_catalog_pipeline.py"
spec = importlib.util.spec_from_file_location("card_catalog_pipeline", SCRIPT)
pipeline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pipeline)

class CatalogPipelineTests(unittest.TestCase):
    def test_import_cannot_self_assert_verified_status(self):
        row = pipeline.normalize({
            "countryCode":"PK", "institutionName":"Example Bank",
            "institutionType":"bank", "officialWebsite":"https://example.com",
            "verificationStatus":"official_card_verified"
        })
        self.assertEqual(row["verificationStatus"], "unverified")

    def test_same_source_preserves_existing_review_status(self):
        catalog = {"records":[{
            "countryCode":"PK", "institutionName":"Example Bank",
            "institutionType":"bank", "officialWebsite":"https://example.com",
            "sourceUrl":"https://example.com/cards",
            "verificationStatus":"review_required",
            "lastCheckedAt":"2026-01-01T00:00:00+00:00",
            "sourceContentSha256":"oldhash"
        }]}
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"import.json"
            path.write_text('[{"countryCode":"PK","institutionName":"Example Bank","institutionType":"bank","officialWebsite":"https://example.com","sourceUrl":"https://example.com/cards","verificationStatus":"official_card_verified"}]')
            pipeline.import_records(catalog,[str(path)])
        self.assertEqual(catalog["records"][0]["verificationStatus"],"review_required")
        self.assertEqual(catalog["records"][0]["sourceContentSha256"],"oldhash")

    def test_changed_source_resets_verification_history(self):
        catalog = {"records":[{
            "countryCode":"PK", "institutionName":"Example Bank",
            "institutionType":"bank", "officialWebsite":"https://example.com",
            "sourceUrl":"https://example.com/old",
            "verificationStatus":"official_card_verified",
            "sourceContentSha256":"oldhash"
        }]}
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/"import.json"
            path.write_text('[{"countryCode":"PK","institutionName":"Example Bank","institutionType":"bank","officialWebsite":"https://example.com","sourceUrl":"https://example.com/new"}]')
            pipeline.import_records(catalog,[str(path)])
        self.assertEqual(catalog["records"][0]["verificationStatus"],"unverified")
        self.assertIsNone(catalog["records"][0]["sourceContentSha256"])

if __name__ == "__main__":
    unittest.main()
