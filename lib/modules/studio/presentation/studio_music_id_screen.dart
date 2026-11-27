import 'package:flutter/material.dart';
import '../application/services/studio_music_identification_service.dart';
import '../application/services/studio_processing_queue_service.dart';
import '../domain/entities/studio_media_file.dart';
import '../engines/audio_fingerprint/studio_audio_fingerprint_matcher.dart';

class StudioMusicIdScreen extends StatefulWidget {
  const StudioMusicIdScreen({super.key, required this.section});
  final String section;
  @override
  State<StudioMusicIdScreen> createState()=>_StudioMusicIdScreenState();
}
class _StudioMusicIdScreenState extends State<StudioMusicIdScreen>{
  final _service=StudioMusicIdentificationService();
  List<StudioMediaFile> _files=[];
  List<StudioAudioCandidate> _candidates=[];
  List<Map<String,Object?>> _history=[];
  bool _loading=true,_processing=false;
  String? _scanSummary;
  String? _error,_first,_second;
  StudioAudioFingerprintMatch? _result;
  bool get _isCompareMode=>widget.section=='Compare';
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    setState(()=>_loading=true);
    try{
      final files=await _service.audioFiles();
      final history=await _service.comparisonHistory();
      if(!mounted)return;
      files.sort((a,b)=>a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase()));
      setState(()=>_files=files);
      setState(()=>_history=history);
      _first??=files.isNotEmpty?files.first.id:null;
      _second??=files.length>1?files[1].id:null;
      setState(()=>_loading=false);
    }catch(e){if(!mounted)return;setState(()=>_error=e.toString());setState(()=>_loading=false);}
  }
  Future<void> _identify(StudioMediaFile file)async{
    setState(()=>_processing=true);
    try{
      await StudioProcessingQueueService().runFingerprintJob(mediaId: file.id, mediaType: 'audio');
      final scan=await _service.scanMatches(file.id);
      final matches=scan.matches;
      if(!mounted)return;
      setState(()=>_candidates=matches);
      final summary='Compared ${scan.comparedCount} files; skipped ${scan.skippedCount} unreadable/unsupported files.';
      setState(()=>_scanSummary=summary);
      _toast(matches.isEmpty?'No matching candidates. $summary':'Scan completed. ${matches.length} candidates. $summary');
    }catch(e){_toast('Music ID failed: $e');}
    if(mounted)setState(()=>_processing=false);
  }
  Future<void> _runComparison()async{
    if(_first==null||_second==null||_first==_second){_toast('Select two different audio files.');return;}
    setState(()=>_processing=true);
    try{final result=await _service.compare(_first!,_second!);final history=await _service.comparisonHistory();if(!mounted)return;setState(()=>_result=result);setState(()=>_history=history);}
    catch(e){_toast('Comparison failed: $e');}
    if(mounted)setState(()=>_processing=false);
  }
  void _toast(String text){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}
  String _pct(double value)=>(value*100).toStringAsFixed(1)+'%';
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:Text(widget.section)),body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):RefreshIndicator(onRefresh:_load,child:_isCompareMode?_compareBody():_musicBody()));
  }
  Widget _musicBody()=>ListView(padding:const EdgeInsets.all(16),children:[
    const Text('Scan a selected audio file against other compatible files in the local Studio library.'),
    const SizedBox(height:10),
    if(_files.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:50),child:Text('Import audio files in Media Library first.')),
    ..._files.map((f)=>ListTile(leading:const Icon(Icons.audio_file),title:Text(f.originalName),subtitle:Text(f.fileExtension??'Audio'),trailing:IconButton(onPressed:_processing?null:()=>_identify(f),icon:const Icon(Icons.fingerprint),tooltip:'Identify in library'))),
    if(_scanSummary!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_scanSummary!,style:Theme.of(context).textTheme.bodySmall)),
    if(_candidates.isNotEmpty)...[
      const Divider(height:30),
      Text('Candidate matches',style:Theme.of(context).textTheme.titleMedium),
      ..._candidates.map((candidate)=>ListTile(title:Text(candidate.media.originalName),subtitle:Text('Confidence: '+_pct(candidate.match.confidence)+' • '+candidate.match.matchedLandmarks.toString()+' landmarks'),trailing:Icon(candidate.match.isMatch?Icons.check_circle_outline:Icons.info_outline))),
      const Text('Similarity results are candidate signals, not proof of ownership or infringement.'),
    ],
  ]);
  Widget _compareBody(){
    final choices=_files.map((f)=>DropdownMenuItem<String>(value:f.id,child:Text(f.originalName,overflow:TextOverflow.ellipsis))).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      if(_files.length<2)const Text('Import at least two audio files in Media Library to compare.'),
      DropdownButtonFormField<String>(value:_files.any((f)=>f.id==_first)?_first:null,items:choices,decoration:const InputDecoration(labelText:'First audio',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>_first=v)),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:_files.any((f)=>f.id==_second)?_second:null,items:choices,decoration:const InputDecoration(labelText:'Second audio',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>_second=v)),
      const SizedBox(height:18),
      FilledButton.icon(onPressed:_processing||_files.length<2?null:_runComparison,icon:const Icon(Icons.compare_arrows),label:Text(_processing?'Processing…':'Compare audio')),
      if(_result!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_result!.isMatch?'Potential audio match':'No strong match found',style:Theme.of(context).textTheme.titleMedium),
        Text('Confidence: '+_pct(_result!.confidence)),
        Text('Matched landmarks: ${_result!.matchedLandmarks} / ${_result!.queryLandmarks} query'),
        Text('Query coverage: '+_pct(_result!.queryCoverage)),
        Text('Reference coverage: '+_pct(_result!.referenceCoverage)),
        Text('Estimated offset: ${_result!.offsetMs} ms'),
        const SizedBox(height:8),const Text('Local fingerprint similarity is a candidate signal, not proof of ownership or infringement.'),
      ]))),
      if(_history.isNotEmpty)Padding(padding:const EdgeInsets.only(top:20),child:Text('Recent comparisons',style:Theme.of(context).textTheme.titleMedium)),
      ..._history.take(20).map((h)=>ListTile(dense:true,title:Text(h['left_name'].toString()+' vs '+h['right_name'].toString()),subtitle:Text('Score: '+((h['match_score'] as num).toDouble()*100).toStringAsFixed(1)+'% • '+h['matched_landmarks'].toString()+' landmarks'),leading:const Icon(Icons.history))),
    ]);
  }
}
