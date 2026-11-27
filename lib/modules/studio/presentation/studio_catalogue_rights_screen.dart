import 'package:flutter/material.dart';
import '../application/services/studio_catalogue_rights_service.dart';

class StudioCatalogueRightsScreen extends StatefulWidget {
  const StudioCatalogueRightsScreen({super.key, required this.section});
  final String section;
  @override
  State<StudioCatalogueRightsScreen> createState() => _StudioCatalogueRightsScreenState();
}

class _StudioCatalogueRightsScreenState extends State<StudioCatalogueRightsScreen> with SingleTickerProviderStateMixin {
  final _service = StudioCatalogueRightsService();
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String,Object?>> _tracks = [], _artists = [], _releases = [], _holders = [], _ownerships = [], _licenses = [];
  bool get _rights => widget.section == 'Rights Management';

  @override
  void initState(){super.initState();_tabs=TabController(length:3,vsync:this);_reload();}
  @override
  void dispose(){_tabs.dispose();super.dispose();}
  Future<void> _reload() async {
    setState(()=>_loading=true);
    try{
      if(_rights){
        final data=await Future.wait([_service.holders(),_service.ownerships(),_service.licenses()]);
        if(!mounted)return;setState((){_holders=data[0];_ownerships=data[1];_licenses=data[2];_loading=false;});
      }else{
        final data=await Future.wait([_service.tracks(),_service.artists(),_service.releases()]);
        if(!mounted)return;setState((){_tracks=data[0];_artists=data[1];_releases=data[2];_loading=false;});
      }
    }catch(e){if(!mounted)return;setState(()=>_error=e.toString());setState(()=>_loading=false);}
  }
  Future<String?> _ask(String title,String label,{String initial=''})async{
    final c=TextEditingController(text:initial);
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),content:TextField(controller:c,autofocus:true,decoration:InputDecoration(labelText:label)),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Save'))]));
    final value=result?.trim();c.dispose();return value==null||value.isEmpty?null:value;
  }
  void _toast(String message){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}
  Future<void> _addTrack()async{final v=await _ask('Add track','Track title');if(v==null)return;try{await _service.addTrack(v);await _reload();}catch(e){_toast('Save failed: $e');}}
  Future<void> _addArtist()async{final v=await _ask('Add artist','Display name');if(v==null)return;try{await _service.addArtist(v);await _reload();}catch(e){_toast('Save failed: $e');}}
  Future<void> _addRelease()async{final v=await _ask('Add release','Release title');if(v==null)return;final type=await _ask('Release type','Album, EP, single',initial:'album')??'album';try{await _service.addRelease(v,releaseType:type);await _reload();}catch(e){_toast('Save failed: $e');}}
  Future<void> _addHolder()async{final v=await _ask('Add rights holder','Name');if(v==null)return;final type=await _ask('Holder type','Individual or business',initial:'individual')??'individual';try{await _service.addHolder(name:v,type:type);await _reload();}catch(e){_toast('Save failed: $e');}}
  Future<Map<String,Object?>?> _selectHolder()=>showDialog<Map<String,Object?>>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Select holder'),content:SizedBox(width:320,child:ListView(shrinkWrap:true,children:_holders.map((h)=>ListTile(title:Text(h['name'].toString()),subtitle:Text(h['holder_type'].toString()),onTap:()=>Navigator.pop(ctx,h))).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel'))]));
  Future<void> _addOwnership()async{
    if(_holders.isEmpty){_toast('Add a rights holder first.');return;}final h=await _selectHolder();if(h==null)return;
    final type=await _ask('Ownership','Asset type (track/release/composition)');if(type==null)return;final id=await _ask('Ownership','Asset ID');if(id==null)return;final shareText=await _ask('Ownership','Share percentage');if(shareText==null)return;final share=double.tryParse(shareText);if(share==null||share<=0||share>100){_toast('Share must be greater than 0 and up to 100%.');return;}final territory=await _ask('Ownership','Territory',initial:'Worldwide')??'Worldwide';
    try{await _service.addOwnership(holderId:h['id'].toString(),assetType:type,assetId:id,share:share,territory:territory);await _reload();}catch(e){_toast('Save failed: $e');}
  }
  Future<void> _addLicense()async{
    final type=await _ask('License','Asset type');if(type==null)return;final id=await _ask('License','Asset ID');if(id==null)return;final licensor=await _ask('License','Licensor');if(licensor==null)return;final licensee=await _ask('License','Licensee');if(licensee==null)return;final usage=await _ask('License','Usage type');if(usage==null)return;final territory=await _ask('License','Territory',initial:'Worldwide')??'Worldwide';
    try{await _service.addLicense(assetType:type,assetId:id,licensor:licensor,licensee:licensee,usage:usage,territory:territory);await _reload();}catch(e){_toast('Save failed: $e');}
  }
  Widget _list(List<Map<String,Object?>> rows,String Function(Map<String,Object?>) title,String Function(Map<String,Object?>) subtitle){
    return RefreshIndicator(onRefresh:_reload,child:rows.isEmpty?ListView(children:const [SizedBox(height:180),Center(child:Text('No records yet. Tap + to add.'))]):ListView.builder(itemCount:rows.length,itemBuilder:(ctx,i)=>ListTile(title:Text(title(rows[i])),subtitle:Text(subtitle(rows[i])))));
  }
  Future<void> _addCurrent()async{
    if(_rights){if(_tabs.index==0)await _addHolder();else if(_tabs.index==1)await _addOwnership();else await _addLicense();}
    else{if(_tabs.index==0)await _addTrack();else if(_tabs.index==1)await _addArtist();else await _addRelease();}
  }
  @override
  Widget build(BuildContext context){
    return Scaffold(appBar:AppBar(title:Text(widget.section),bottom:TabBar(controller:_tabs,tabs:_rights?const [Tab(text:'Holders'),Tab(text:'Ownership'),Tab(text:'Licenses')]:const [Tab(text:'Tracks'),Tab(text:'Artists'),Tab(text:'Releases')])),
      floatingActionButton:FloatingActionButton(onPressed:_addCurrent,child:const Icon(Icons.add)),
      body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):_rights?_rightsBody():_catalogueBody());
  }
  Widget _catalogueBody()=>TabBarView(controller:_tabs,children:[
    _list(_tracks,(r)=>r['title'].toString(),(r)=>r['id'].toString()),
    _list(_artists,(r)=>r['display_name'].toString(),(r)=>r['legal_name']?.toString()??r['id'].toString()),
    _list(_releases,(r)=>r['title'].toString(),(r)=>r['release_type'].toString()),
  ]);
  Widget _rightsBody()=>TabBarView(controller:_tabs,children:[
    _list(_holders,(r)=>r['name'].toString(),(r)=>r['holder_type'].toString()),
    _list(_ownerships,(r)=>r['holder_name'].toString()+' — '+r['share_percent'].toString()+'%',(r)=>r['asset_type'].toString()+' / '+r['asset_id'].toString()+' • '+r['territory'].toString()),
    _list(_licenses,(r)=>r['licensor'].toString()+' → '+r['licensee'].toString(),(r)=>r['usage_type'].toString()+' • '+r['asset_type'].toString()+' '+r['asset_id'].toString()+' • '+r['territory'].toString()),
  ]);
}
