import 'package:flutter/material.dart';
import '../application/services/studio_reports_service.dart';
import '../infrastructure/storage/studio_storage_manager.dart';
import '../infrastructure/database/studio_database_manager.dart';

class StudioManagementScreen extends StatefulWidget{
  const StudioManagementScreen({super.key});
  @override State<StudioManagementScreen> createState()=>_StudioManagementScreenState();
}
class _StudioManagementScreenState extends State<StudioManagementScreen>{
  late Future<_Diagnostics> _future;
  @override void initState(){super.initState();_future=_load();}
  Future<_Diagnostics> _load()async{
    final summary=await StudioReportsService().load();
    final bytes=await StudioStorageManager().calculateTotalBytes();
    final db=await StudioDatabaseManager.instance.initialize();
    return _Diagnostics(summary,bytes,db.isOpen);
  }
  void _refresh(){setState(()=>_future=_load());}
  String _size(int bytes){if(bytes<1024)return '$bytes B';if(bytes<1024*1024)return (bytes/1024).toStringAsFixed(1)+' KB';if(bytes<1024*1024*1024)return (bytes/(1024*1024)).toStringAsFixed(1)+' MB';return (bytes/(1024*1024*1024)).toStringAsFixed(2)+' GB';}
  Widget _item(BuildContext context,String label,String value,IconData icon){final color=Theme.of(context).colorScheme;return Card(child:ListTile(leading:Icon(icon,color:color.primary),title:Text(label),subtitle:Text(value)));}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Studio Management'),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),body:FutureBuilder<_Diagnostics>(future:_future,builder:(context,s){
    if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
    if(s.hasError)return Center(child:Text('Diagnostics failed: ${s.error}'));
    final d=s.data!;final r=d.summary;
    return RefreshIndicator(onRefresh:()=>_future.then((_)=>_refresh()),child:ListView(padding:const EdgeInsets.all(16),children:[
      Text('System Diagnostics',style:Theme.of(context).textTheme.titleMedium),
      _item(context,'Studio database',d.databaseOpen?'Connected':'Not connected',Icons.storage),
      _item(context,'Database version','V1',Icons.data_object),
      _item(context,'Managed storage used',_size(d.storageBytes),Icons.folder_open),
      _item(context,'Total media',r.media.toString(),Icons.perm_media),
      _item(context,'Fingerprint artifacts',r.fingerprints.toString(),Icons.fingerprint),
      _item(context,'Active processing jobs',r.pendingJobs.toString(),Icons.pending_actions),
      _item(context,'Failed processing jobs',r.failedJobs.toString(),Icons.error_outline),
      const SizedBox(height:12),
      const Text('Management controls for queue retry/cancel, storage cleanup, database reset, and algorithm configuration will be enabled as their respective operations are implemented. No destructive controls are exposed in this diagnostic screen.'),
    ]));
  }));
}
class _Diagnostics{
  const _Diagnostics(this.summary,this.storageBytes,this.databaseOpen);
  final StudioReportSummary summary;final int storageBytes;final bool databaseOpen;
}
