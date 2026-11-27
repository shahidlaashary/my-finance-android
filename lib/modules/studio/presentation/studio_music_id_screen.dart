import 'package:flutter/material.dart';
import '../application/services/studio_music_identification_service.dart';
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
  List<Map<String,Object?>> _history=[];
  bool _loading=true;
  String? _error;
  String? _first,_second;
  bool _processing=false;
  StudioAudioFingerprintMatch? _result;
  bool get _compare=>widget.section=='Compare';
  @override void initState(){super.initState();_load();}
  Future<void> _load()async{
    setState(()=>_loading=true);
    try{final data=await _service.audioFiles();final history=await _service.comparisonHistory();if(!mounted)return;setState(()=>_files=data..sort((a,b)=>a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase())));setState(()=>_history=history);_first??=data.isNotEmpty?data.first.id:null;_second??=data.length>1?data[1].id:null;setState(()=>_loading=false);}
    catch(e){if(!mounted)return;setState(()=>_error=e.toString());setState(()=>_loading=false);}
  }
  Future<void> _runId(StudioMediaFile file)async{
    setState(()=>_processing=true);
    try{final fp=await _service.identify(file.id);if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Fingerprint generated: ${fp.frameCount} analysis frames')));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Music ID failed: $e')));}
    if(mounted)setState(()=>_processing=false);
  }
  Future<void> _runCompare()async{
    if(_first==null||_second==null||_first==_second){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Select two different audio files.')));return;}
    setState(()=>_processing=true);
    try{final result=await _service.compare(_first!,_second!);if(!mounted)return;setState(()=>_result=result);}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Comparison failed: $e')));}
    if(mounted)setState(()=>_processing=false);
  }
  String _percent(double value)=>(value*100).toStringAsFixed(1)+'%';
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:Text(widget.section)),body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):RefreshIndicator(onRefresh:_load,child:_compare?_compareBody():_musicBody()));
  }
  Widget _musicBody()=>_files.isEmpty?ListView(children:const [SizedBox(height:200),Center(child:Text('Import audio files in Media Library first.'))]:ListView.builder(itemCount:_files.length,itemBuilder:(ctx,i){final f=_files[i];return ListTile(leading:const Icon(Icons.audio_file),title:Text(f.originalName),subtitle:Text(f.fileExtension??'Audio file'),trailing:IconButton(onPressed:_processing?null:()=>_runId(f),icon:const Icon(Icons.fingerprint),tooltip:'Generate fingerprint'));});
  Widget _compareBody(){
    final choices=_files.map((f)=>DropdownMenuItem<String>(value:f.id,child:Text(f.originalName,overflow:TextOverflow.ellipsis))).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      if(_files.length<2)const Text('Import at least two audio files in Media Library to compare.'),
      DropdownButtonFormField<String>(value:_files.any((f)=>f.id==_first)?_first:null,items:choices,decoration:const InputDecoration(labelText:'First audio',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>_first=v)),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(value:_files.any((f)=>f.id==_second)?_second:null,items:choices,decoration:const InputDecoration(labelText:'Second audio',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>_second=v)),
      const SizedBox(height:18),FilledButton.icon(onPressed:_processing||_files.length<2?null:onPressedCompare,icon:const Icon(Icons.compare_arrows),label:Text(_processing?'Processing…':'Compare audio')),
      if(_history.isNotEmpty)Padding(padding:const EdgeInsets.only(top:20),child:Text('Recent comparisons',style:Theme.of(context).textTheme.titleMedium)),\n      ..._history.take(20).map((h)=>ListTile(dense:true,title:Text(h['left_name'].toString()+' vs '+h['right_name'].toString()),subtitle:Text('Score: '+((h['match_score'] as num).toDouble()*100).toStringAsFixed(1)+'% • '+h['matched_landmarks'].toString()+' landmarks'),leading:const Icon(Icons.history))),\n      if(_result!=null)Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_result!.isMatch?'Potential audio match':'No strong match found',style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),Text('Confidence: ${_percent(_result!.confidence)}'),
        Text('Matched landmarks: ${_result!.matchedLandmarks} / ${_result!.queryLandmarks} query'),
        Text('Query coverage: ${_percent(_result!.queryCoverage)}'),
        Text('Reference coverage: ${_percent(_result!.referenceCoverage)}'),
        Text('Estimated offset: ${_result!.offsetMs} ms'),
        const SizedBox(height:8),const Text('Local fingerprint similarity is a candidate signal, not proof of ownership or infringement.'),
      ]))),
    ]);
  }
  void onPressedCompare()=>_runCompare();
}
