import 'package:flutter/material.dart';
import '../application/services/studio_video_identification_service.dart';
import '../domain/entities/studio_media_file.dart';
import '../engines/video_fingerprint/studio_video_fingerprint_engine.dart';

class StudioVideoIdScreen extends StatefulWidget{
  const StudioVideoIdScreen({super.key});
  @override State<StudioVideoIdScreen> createState()=>_StudioVideoIdScreenState();
}
class _StudioVideoIdScreenState extends State<StudioVideoIdScreen>{
  final _service=StudioVideoIdentificationService();
  List<StudioMediaFile> _videos=[];\n  List<Map<String,Object?>> _history=[];
  String? _first,_second;
  bool _loading=true,_busy=false;
  StudioVideoFingerprintMatch? _result;
  String? _error;
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{setState(()=>_loading=true);try{final data=await _service.videos();final history=await _service.history();if(!mounted)return;setState(()=>_videos=data..sort((a,b)=>a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase())));setState(()=>_history=history.where((h)=>h['algorithm_key']==StudioVideoFingerprintEngine.key).toList());_first??=data.isNotEmpty?data.first.id:null;_second??=data.length>1?data[1].id:null;setState(()=>_loading=false);}catch(e){if(!mounted)return;setState(()=>_error=e.toString());setState(()=>_loading=false);}}
  Future<void> _fingerprint(StudioMediaFile f)async{setState(()=>_busy=true);try{await _service.fingerprint(f.id);if(mounted)_toast('Video fingerprint generated.');}catch(e){if(mounted)_toast('Fingerprint failed: $e');}if(mounted)setState(()=>_busy=false);}
  Future<void> _compare()async{if(_first==null||_second==null||_first==_second){_toast('Choose two different videos.');return;}setState(()=>_busy=true);try{final m=await _service.compare(_first!,_second!);final history=await _service.history();if(mounted)setState(()=>_result=m);if(mounted)setState(()=>_history=history.where((h)=>h['algorithm_key']==StudioVideoFingerprintEngine.key).toList());}catch(e){if(mounted)_toast('Compare failed: $e');}if(mounted)setState(()=>_busy=false);}
  void _toast(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  String _pct(double v)=>(v*100).toStringAsFixed(1)+'%';
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Video ID')),body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):RefreshIndicator(onRefresh:_load,child:_body()));
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
    FilledButton.icon(onPressed:_busy||_videos.length<2?null:_compare,icon:const Icon(Icons.compare_arrows),label:Text(_busy?'Processing…':'Compare')),
    if(_history.isNotEmpty)Padding(padding:const EdgeInsets.only(top:18),child:Text('Recent video comparisons',style:Theme.of(context).textTheme.titleMedium)),\n    ..._history.take(20).map((h)=>ListTile(dense:true,title:Text(h['left_name'].toString()+' vs '+h['right_name'].toString()),subtitle:Text('Score: '+((h['match_score'] as num).toDouble()*100).toStringAsFixed(1)+'% • '+h['matched_landmarks'].toString()+' frames'),leading:const Icon(Icons.history))),\n    if(_result!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(_result!.isMatch?'Potential visual match':'No strong visual match',style:Theme.of(context).textTheme.titleMedium),
      Text('Confidence: ${_pct(_result!.confidence)}'),
      Text('Matched frames: ${_result!.matches} / ${_result!.queryFrames} query frames'),
      Text('Reference frames: ${_result!.referenceFrames}'),
      Text('Estimated offset: ${_result!.offsetMs} ms'),
      const SizedBox(height:8),const Text('Frame similarity is a candidate signal and may produce false positives, especially for static scenes.'),
    ]))),
  ]);
}
