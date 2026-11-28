import 'package:flutter/material.dart';
import '../application/services/studio_visual_match_service.dart';
import '../application/services/studio_processing_queue_service.dart';
import '../domain/entities/studio_media_file.dart';
import '../domain/entities/studio_video_fingerprint_match.dart';

class StudioVisualMatchScreen extends StatefulWidget{
  const StudioVisualMatchScreen({super.key});
  @override State<StudioVisualMatchScreen> createState()=>_StudioVisualMatchScreenState();
}
class _StudioVisualMatchScreenState extends State<StudioVisualMatchScreen>{
  final _service=StudioVisualMatchService();
  List<StudioMediaFile> _videos=[];
  List<Map<String,Object?>> _history=[];
  List<StudioVisualMatchCandidate> _scanCandidates=[];
  String? _scanSummary, _scanProgress;
  String? _first,_second;
  bool _loading=true,_busy=false;
  StudioVideoFingerprintMatch? _result;
  String? _error;
  int _loadGeneration=0;
  @override void initState(){super.initState();_load();}
  @override void dispose(){_loadGeneration++;super.dispose();}
  Future<void> _load()async{
    final generation=++_loadGeneration;
    if(mounted)setState(()=>_loading=true);
    try{
      final data=await _service.videos();
      final history=await _service.history();
      if(!mounted||generation!=_loadGeneration)return;
      data.sort((a,b)=>a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase()));
      setState((){
        _videos=data;
        _history=history.where((h)=>h['algorithm_key']==StudioVisualMatchService.algorithmKey).toList();
        _first??=data.isNotEmpty?data.first.id:null;
        _second??=data.length>1?data[1].id:null;
        _error=null;
        _loading=false;
      });
    }catch(e){
      if(!mounted||generation!=_loadGeneration)return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  Future<void> _fingerprint(StudioMediaFile f)async{setState(()=>_busy=true);try{await StudioProcessingQueueService().runFingerprintJob(mediaId: f.id, mediaType: 'video');if(mounted)_toast('Video fingerprint generated.');}catch(e){if(mounted)_toast('Fingerprint failed: $e');}if(mounted)setState(()=>_busy=false);}
  Future<void> _scanLibrary() async {
    if (_first == null) return;
    setState(() { _busy = true; _scanCandidates = []; _scanSummary = null; _scanProgress = 'Starting scan…'; });
    try {
      final result = await _service.scanMatches(_first!, onProgress: (done, total) {
        if (mounted) setState(() => _scanProgress = total == 0 ? 'No other videos to compare.' : 'Comparing $done of $total videos…');
      });
      final history = await _service.history();
      if (mounted) setState(() {
        _scanCandidates = result.matches;
        _scanSummary = 'Compared ${result.comparedCount} videos; skipped ${result.skippedCount} unreadable files.';
        _history = history.where((h) => h['algorithm_key'] == StudioVisualMatchService.algorithmKey).toList();
        _scanProgress = null;
      });
    } catch (e) {
      if (mounted) { _scanProgress = null; _toast('Library scan failed: $e'); }
    } finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _compare()async{if(_first==null||_second==null||_first==_second){_toast('Choose two different videos.');return;}setState(()=>_busy=true);try{final m=await _service.compare(_first!,_second!);final history=await _service.history();if(mounted)setState(()=>_result=m);if(mounted)setState(()=>_history=history.where((h)=>h['algorithm_key']==StudioVisualMatchService.algorithmKey).toList());}catch(e){if(mounted)_toast('Compare failed: $e');}if(mounted)setState(()=>_busy=false);}
  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _pct(double v)=>(v*100).toStringAsFixed(1)+'%';
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Visual Match')),
    body:_loading
      ?const Center(child:CircularProgressIndicator())
      :_error!=null
        ?Center(child:Padding(
          padding:const EdgeInsets.all(24),
          child:Column(mainAxisSize:MainAxisSize.min,children:[
            const Icon(Icons.error_outline_rounded,size:40),
            const SizedBox(height:12),
            Text('Could not load Visual Match: $_error',textAlign:TextAlign.center),
            const SizedBox(height:12),
            FilledButton.tonalIcon(onPressed:_load,icon:const Icon(Icons.refresh_rounded),label:const Text('Retry')),
          ]),
        ))
        :RefreshIndicator(onRefresh:_load,child:_body()),
  );
  Widget _body()=>ListView(padding:const EdgeInsets.all(16),children:[
    if(_videos.isEmpty)const Padding(padding:EdgeInsets.symmetric(vertical:60),child:Text('Import video files in Media Library first.')),
    if(_videos.isNotEmpty)Text('Video Library',style:Theme.of(context).textTheme.titleMedium),
    ..._videos.map((v)=>ListTile(leading:const Icon(Icons.video_file_outlined),title:Text(v.originalName),subtitle:Text(v.durationMs==null?'Video file':(v.durationMs!/1000).toStringAsFixed(1)+' sec'),trailing:IconButton(onPressed:_busy?null:()=>_fingerprint(v),icon:const Icon(Icons.fingerprint),tooltip:'Generate video fingerprint'))),
    const Divider(height:28),
    Text('Compare videos',style:Theme.of(context).textTheme.titleMedium),
    DropdownButtonFormField<String>(value:_videos.any((v)=>v.id==_first)?_first:null,items:_videos.map((v)=>DropdownMenuItem(value:v.id,child:Text(v.originalName,overflow:TextOverflow.ellipsis))).toList(),decoration:const InputDecoration(labelText:'First video'),onChanged:(v)=>setState(()=>_first=v)),
    const SizedBox(height:12),
    DropdownButtonFormField<String>(value:_videos.any((v)=>v.id==_second)?_second:null,items:_videos.map((v)=>DropdownMenuItem(value:v.id,child:Text(v.originalName,overflow:TextOverflow.ellipsis))).toList(),decoration:const InputDecoration(labelText:'Second video'),onChanged:(v)=>setState(()=>_second=v)),
    const SizedBox(height:14),
    FilledButton.icon(onPressed:_busy||_videos.length<2?null:_compare,icon:const Icon(Icons.compare_arrows),label:Text(_busy?'Processing…':'Compare two videos')),
    const SizedBox(height:10),
    OutlinedButton.icon(onPressed:_busy||_videos.length<2?null:_scanLibrary,icon:const Icon(Icons.search_rounded),label:Text(_busy?'Scanning…':'Scan selected video against library')),
    if(_scanProgress!=null)Padding(padding:const EdgeInsets.only(top:8),child:Text(_scanProgress!,style:Theme.of(context).textTheme.bodySmall)),
    if(_scanSummary!=null)Padding(padding:const EdgeInsets.only(top:10),child:Text(_scanSummary!,style:Theme.of(context).textTheme.bodySmall)),
    if(_scanSummary!=null&&_scanCandidates.isEmpty)const Padding(padding:EdgeInsets.only(top:8),child:Text('No strong visual matches were found for this video.')),
    if(_scanCandidates.isNotEmpty)Padding(padding:const EdgeInsets.only(top:18),child:Text('Library matches (${_scanCandidates.length})',style:Theme.of(context).textTheme.titleMedium)),
    ..._scanCandidates.map((c)=>Card(child:ListTile(leading:const Icon(Icons.movie_filter_outlined),title:Text(c.media.originalName),subtitle:Text('${_pct(c.match.confidence)} confidence • ${c.match.matches} matching frames • offset ${c.match.offsetMs} ms'),))),
    if(_history.isNotEmpty)Padding(padding:const EdgeInsets.only(top:18),child:Text('Recent video comparisons',style:Theme.of(context).textTheme.titleMedium)),
    ..._history.take(20).map((h)=>ListTile(dense:true,title:Text(h['left_name'].toString()+' vs '+h['right_name'].toString()),subtitle:Text('Score: '+((h['match_score'] as num).toDouble()*100).toStringAsFixed(1)+'% • '+h['matched_landmarks'].toString()+' frames'),leading:const Icon(Icons.history))),
    if(_result!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(_result!.isMatch?'Potential visual match':'No strong visual match',style:Theme.of(context).textTheme.titleMedium),
      Text('Confidence: ${_pct(_result!.confidence)}'),
      Text('Matched frames: ${_result!.matches} / ${_result!.queryFrames} query frames'),
      Text('Reference frames: ${_result!.referenceFrames}'),
      Text('Estimated offset: ${_result!.offsetMs} ms'),
      if (_result!.matchedQueryTimestampsMs.isNotEmpty) Text('Matched query timestamps: ${_result!.matchedQueryTimestampsMs.take(6).map((ms) => (ms / 1000).toStringAsFixed(1) + 's').join(', ')}'),
      if (_result!.matchedReferenceTimestampsMs.isNotEmpty) Text('Matched reference timestamps: ${_result!.matchedReferenceTimestampsMs.take(6).map((ms) => (ms / 1000).toStringAsFixed(1) + 's').join(', ')}'),
      const SizedBox(height:8),const Text('Frame similarity is a candidate signal and may produce false positives, especially for static scenes.'),
    ]))),
  ]);
}
