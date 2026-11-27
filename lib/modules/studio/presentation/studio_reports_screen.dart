import 'package:flutter/material.dart';
import '../application/services/studio_reports_service.dart';

class StudioReportsScreen extends StatefulWidget {
  const StudioReportsScreen({super.key});
  @override
  State<StudioReportsScreen> createState()=>_StudioReportsScreenState();
}
class _StudioReportsScreenState extends State<StudioReportsScreen>{
  late Future<StudioReportSummary> _future;
  @override void initState(){super.initState();_future=StudioReportsService().load();}
  Future<void> _refresh()async{final next=StudioReportsService().load();setState(()=>_future=next);await next;}
  Widget _stat(BuildContext context,String title,int value,IconData icon){
    final colors=Theme.of(context).colorScheme;
    return Card(child:Padding(padding:const EdgeInsets.all(14),child:Row(children:[
      Icon(icon,color:colors.primary,size:24),const SizedBox(width:12),Expanded(child:Text(title)),Text(value.toString(),style:Theme.of(context).textTheme.titleLarge),
    ])));
  }
  @override Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:const Text('Studio Reports'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),
      body:FutureBuilder<StudioReportSummary>(future:_future,builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(s.hasError)return Center(child:Text('Report loading failed: ${s.error}'));
        final d=s.data!;
        return RefreshIndicator(onRefresh:_refresh,child:ListView(padding:const EdgeInsets.all(16),children:[
          Text('Media overview',style:Theme.of(context).textTheme.titleMedium),
          _stat(context,'Total media files',d.media,Icons.perm_media_outlined),
          _stat(context,'Audio files',d.audio,Icons.music_note),
          _stat(context,'Video files',d.video,Icons.video_library),
          _stat(context,'Fingerprints generated',d.fingerprints,Icons.fingerprint),
          const SizedBox(height:12),
          Text('Catalogue & Rights',style:Theme.of(context).textTheme.titleMedium),
          _stat(context,'Tracks',d.tracks,Icons.library_music),
          _stat(context,'Artists',d.artists,Icons.person),
          _stat(context,'Releases',d.releases,Icons.album),
          _stat(context,'Rights holders',d.holders,Icons.people_alt),
          _stat(context,'Ownership records',d.ownerships,Icons.verified_user),
          _stat(context,'Licences',d.licenses,Icons.description),
          _stat(context,'Comparisons saved',d.comparisons,Icons.compare_arrows),
          const SizedBox(height:12),
          Text('Processing',style:Theme.of(context).textTheme.titleMedium),
          _stat(context,'Active jobs',d.pendingJobs,Icons.pending_actions),
          _stat(context,'Failed jobs',d.failedJobs,Icons.error_outline),
        ]));
      }),
    );
  }
}
