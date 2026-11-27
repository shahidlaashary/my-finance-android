import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import '../../application/services/studio_fingerprint_catalogue_service.dart';
import '../../application/services/studio_media_library_service.dart';
import '../../domain/entities/studio_fingerprint.dart';
import '../../domain/entities/studio_media_file.dart';
import '../../infrastructure/storage/studio_storage_manager.dart';

class StudioVideoFingerprintMatch {
  const StudioVideoFingerprintMatch({required this.matches,required this.queryFrames,required this.referenceFrames,required this.confidence,required this.offsetMs});
  final int matches,queryFrames,referenceFrames,offsetMs;
  final double confidence;
  bool get isMatch=>matches>=3&&confidence>=0.15;
}

class StudioVideoFingerprintEngine {
  StudioVideoFingerprintEngine({required StudioStorageManager storage,required StudioMediaLibraryService media,required StudioFingerprintCatalogueService catalogue,this.sampleIntervalMs=2000,this.maxFrames=300})
    :_storage=storage,_media=media,_catalogue=catalogue;
  final StudioStorageManager _storage;final StudioMediaLibraryService _media;final StudioFingerprintCatalogueService _catalogue;
  final int sampleIntervalMs,maxFrames;
  static const key='studio.video.frame-dhash',version='1.0.0';
  Future<StudioFingerprint> generate(String mediaId) async {
    final source=await _media.getById(mediaId);
    if(source==null)throw StateError('Video file is missing from Studio catalogue.');
    if(source.mediaType!=StudioMediaType.video)throw ArgumentError('Video fingerprint requires a video asset.');
    if(!await File(source.storagePath).exists())throw FileSystemException('Managed video is missing.',source.storagePath);
    final prior=await _catalogue.getForMedia(mediaFileId:source.id,algorithmKey:key,algorithmVersion:version);
    if(prior!=null)return prior;
    var duration=source.durationMs??0;
    if(duration<=0){final controller=VideoPlayerController.file(File(source.storagePath));try{await controller.initialize();duration=controller.value.duration.inMilliseconds;}catch(_){duration=0;}finally{try{await controller.dispose();}catch(_){}}}
    final effectiveInterval=duration>0?max(sampleIntervalMs,(duration/(maxFrames-1)).ceil()):sampleIntervalMs;
    final count=min(maxFrames,max(1,duration>0?(duration~/effectiveInterval)+1:1));
    final artifactBytes=BytesBuilder(copy:false);final segments=<StudioFingerprintSegment>[];
    for(var index=0;index<count;index++){
      final timestamp=index*effectiveInterval;
      final data=await VideoThumbnail.thumbnailData(video:source.storagePath,imageFormat:ImageFormat.JPEG,maxWidth:144,timeMs:timestamp,quality:70);
      if(data==null||data.isEmpty)continue;
      final decoded=img.decodeImage(data);if(decoded==null)continue;
      final hash=_differenceHash(decoded);
      final record=Uint8List(16);final view=ByteData.sublistView(record);
      view.setInt64(0,timestamp,Endian.little);for(var byte=0;byte<8;byte++){record[8+byte]=(hash>>(byte*8))&0xff;}
      final start=artifactBytes.length;artifactBytes.add(record);
      segments.add(StudioFingerprintSegment(fingerprintId:'',segmentIndex:segments.length,startMs:timestamp,endMs:min(duration>0?duration:timestamp+effectiveInterval,timestamp+sampleIntervalMs).toInt(),dataOffsetBytes:start,dataLengthBytes:record.length,signatureHash:hash.toRadixString(16)));
    }
    final bytes=artifactBytes.takeBytes();if(bytes.isEmpty)throw StateError('No video frames could be sampled.');
    final id='fp_video_'+DateTime.now().microsecondsSinceEpoch.toString()+'_'+Random.secure().nextInt(999999).toString();
    final file=await _storage.allocateFingerprintFile(fingerprintId:id,extension:'bin');await file.writeAsBytes(bytes,flush:true);
    final now=DateTime.now().toUtc();
    final fingerprint=StudioFingerprint(id:id,mediaFileId:source.id,mediaType:StudioMediaType.video,algorithmKey:key,algorithmVersion:version,fingerprintFormat:'studio-video-frame-dhash-v1',dataFilePath:file.path,checksumSha256:sha256.convert(bytes).toString(),durationMs:duration>0?duration:null,frameCount:segments.length,status:StudioFingerprintStatus.generated,createdAt:now,updatedAt:now);
    try{await _catalogue.register(fingerprint);await _catalogue.replaceSegments(id,segments.map((s)=>StudioFingerprintSegment(fingerprintId:id,segmentIndex:s.segmentIndex,startMs:s.startMs,endMs:s.endMs,dataOffsetBytes:s.dataOffsetBytes,dataLengthBytes:s.dataLengthBytes,signatureHash:s.signatureHash)).toList());return fingerprint;}catch(_){if(await file.exists())await file.delete();rethrow;}
  }
  int _differenceHash(img.Image image){
    final small=img.copyResize(image,width:9,height:8);
    var hash=0;var bit=0;
    for(var y=0;y<8;y++)for(var x=0;x<8;x++){
      final a=small.getPixel(x,y),b=small.getPixel(x+1,y);
      final la=0.299*a.r.toDouble()+0.587*a.g.toDouble()+0.114*a.b.toDouble();
      final lb=0.299*b.r.toDouble()+0.587*b.g.toDouble()+0.114*b.b.toDouble();
      if(la>lb)hash|=(1<<bit);bit++;
    }
    return hash;
  }
  Future<StudioVideoFingerprintMatch> compare(String queryId,String referenceId) async{
    final q=await _catalogue.getForMedia(mediaFileId:queryId,algorithmKey:key,algorithmVersion:version)??await generate(queryId);
    final r=await _catalogue.getForMedia(mediaFileId:referenceId,algorithmKey:key,algorithmVersion:version)??await generate(referenceId);
    final qbytes=await File(q.dataFilePath).readAsBytes(),rbytes=await File(r.dataFilePath).readAsBytes();
    final qrec=_records(qbytes),rrec=_records(rbytes);
    final offsets=<int,int>{};
    for(final qa in qrec)for(final rb in rrec)if(_distance(qa.hash,rb.hash)<=8){final off=rb.time-qa.time;offsets.update(off,(n)=>n+1,ifAbsent:()=>1);}
    final bestOffset=offsets.entries.isEmpty?0:offsets.entries.reduce((a,b)=>a.value>=b.value?a:b).key;
    final matchedQuery=<int>{};
    for(final qa in qrec)for(final rb in rrec)if(rb.time-qa.time==bestOffset&&_distance(qa.hash,rb.hash)<=8){matchedQuery.add(qa.time);}
    final matches=matchedQuery.length;
    final confidence=qrec.isEmpty||rrec.isEmpty?0.0:2*matches/(qrec.length+rrec.length);
    return StudioVideoFingerprintMatch(matches:matches,queryFrames:qrec.length,referenceFrames:rrec.length,confidence:confidence,offsetMs:bestOffset);
  }
  List<_FrameRecord> _records(Uint8List bytes){if(bytes.length%16!=0)throw const FormatException('Video fingerprint artifact is corrupt.');final d=ByteData.sublistView(bytes);return List.generate(bytes.length~/16,(i){var hash=0;for(var byte=0;byte<8;byte++){hash|=bytes[i*16+8+byte]<<(byte*8);}return _FrameRecord(d.getInt64(i*16,Endian.little),hash);});}
  int _distance(int a,int b){final x=a^b;var n=0;for(var bit=0;bit<64;bit++){if(((x>>bit)&1)!=0)n++;}return n;}
}
class _FrameRecord{const _FrameRecord(this.time,this.hash);final int time,hash;}
