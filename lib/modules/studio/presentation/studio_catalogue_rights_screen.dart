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
  List<Map<String,Object?>> _tracks = [];\n  List<Map<String,Object?>> _artists = [];\n  List<Map<String,Object?>> _releases = [];
  List<Map<String,Object?>> _holders = [];
  List<Map<String,Object?>> _ownerships = [];
  List<Map<String,Object?>> _licenses = [];
  bool get _rights => widget.section == 'Rights Management';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _rights ? 3 : 3, vsync: this);
    _reload();
  }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_rights) {
        final values = await Future.wait([_service.holders(), _service.ownerships(), _service.licenses()]);
        if (!mounted) return;
        setState(() { _holders=values[0]; _ownerships=values[1]; _licenses=values[2]; _loading=false; });
      } else {
        final data=await _service.tracks();
        if(!mounted)return;
        setState(() { _tracks=data; _loading=false; });
      }
    } catch(e) { if(!mounted)return; setState((){_error=e.toString();_loading=false;}); }
  }

  Future<String?> _askText(String title, String label, {String initial=''}) async {
    final c=TextEditingController(text:initial);
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:TextField(controller:c,autofocus:true,decoration:InputDecoration(labelText:label)),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Save'))]));
    final value=result?.trim(); c.dispose(); return (value==null||value.isEmpty)?null:value;
  }
  Future<void> _addTrack() async {
    final title=await _askText('Add catalogue track','Track title'); if(title==null)return;
    try{await _service.addTrack(title);await _reload();}catch(e){_snack('Save failed: $e');}
  }
  Future<void> _addHolder() async {
    final name=await _askText('Add rights holder','Name'); if(name==null)return;
    final type=await _askText('Holder type','Individual or business',initial:'individual')??'individual';
    try{await _service.addHolder(name:name,type:type);await _reload();}catch(e){_snack('Save failed: $e');}
  }
  Future<void> _addOwnership() async {
    if(_holders.isEmpty){_snack('Add a rights holder first.');return;}
    final holder=await _chooseHolder(); if(holder==null)return;
    final assetType=await _askText('Ownership record','Asset type (track, release, composition)'); if(assetType==null)return;
    final assetId=await _askText('Ownership record','Asset ID'); if(assetId==null)return;
    final shareText=await _askText('Ownership record','Ownership share (%)'); if(shareText==null)return;
    final share=double.tryParse(shareText); if(share==null||share<=0||share>100){_snack('Share must be above 0 and at most 100%.');return;}
    final territory=await _askText('Ownership record','Territory',initial:'Worldwide')??'Worldwide';
    try{await _service.addOwnership(holderId:holder['id'].toString(),assetType:assetType,assetId:assetId,share:share,territory:territory);await _reload();}catch(e){_snack('Save failed: $e');}
  }
  Future<Map<String,Object?>?> _chooseHolder() async {
    return showDialog<Map<String,Object?>>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Select rights holder'),content:SizedBox(width:320,child:ListView(shrinkWrap:true,children:_holders.map((holder)=>ListTile(title:Text(holder['name'].toString()),subtitle:Text(holder['holder_type'].toString()),onTap:()=>Navigator.pop(ctx,holder))).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel'))]));
  }
  Future<void> _addLicense() async {
    final assetType=await _askText('License record','Asset type (track, release, video)'); if(assetType==null)return;
    final assetId=await _askText('License record','Asset ID'); if(assetId==null)return;
    final licensor=await _askText('License record','Licensor'); if(licensor==null)return;
    final licensee=await _askText('License record','Licensee'); if(licensee==null)return;
    final usage=await _askText('License record','Usage'); if(usage==null)return;
    final territory=await _askText('License record','Territory',initial:'Worldwide')??'Worldwide';
    try{await _service.addLicense(assetType:assetType,assetId:assetId,licensor:licensor,licensee:licensee,usage:usage,territory:territory);await _reload();}catch(e){_snack('Save failed: $e');}
  }
  void _snack(String message){if(!mounted)return;ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(message)));}

  Widget _list(List<Map<String,Object?>> rows, String Function(Map<String,Object?>) titleFor, String Function(Map<String,Object?>) subtitleFor) {
    return RefreshIndicator(onRefresh:_reload,child:rows.isEmpty?ListView(children:const [SizedBox(height:200),Center(child:Text('No records yet. Tap + to add.'))]):ListView.builder(itemCount:rows.length,itemBuilder:(ctx,i)=>ListTile(title:Text(titleFor(rows[i])),subtitle:Text(subtitleFor(rows[i])))));
  }
  @override
  Widget build(BuildContext context){
    final isCatalogue=!_rights;
    return Scaffold(appBar:AppBar(title:Text(widget.section),bottom:_rights?TabBar(controller:_tabs,tabs:const [Tab(text:'Holders'),Tab(text:'Ownership'),Tab(text:'Licenses')]):null),
      floatingActionButton:FloatingActionButton(onPressed:()=>isCatalogue?_addTrack():_tabs.index==0?_addHolder():_tabs.index==1?_addOwnership():_addLicense(),child:const Icon(Icons.add)),
      body:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Text(_error!)):isCatalogue?_list(_tracks,(r)=>r['title']?.toString()??'',(r)=>r['id']?.toString()??''):_tabBody());
  }
  Widget _catalogueBody()=>TabBarView(controller:_tabs,children:[\n    _list(_tracks,(r)=>r['title']?.toString()??'',(r)=>r['id']?.toString()??''),\n    _list(_artists,(r)=>r['display_name']?.toString()??'',(r)=>r['legal_name']?.toString()??r['id']?.toString()??''),\n    _list(_releases,(r)=>r['title']?.toString()??'',(r)=>r['release_type']?.toString()??''),\n  ]);\n  Widget _tabBody()=>TabBarView(controller:_tabs,children:[
    _list(_holders,(r)=>r['name']?.toString()??'',(r)=>r['holder_type']?.toString()??''),
    _list(_ownerships,(r)=>(r['holder_name'].toString()+' — '+r['share_percent'].toString()+'%'),(r)=>(r['asset_type'].toString()+' / '+r['asset_id'].toString()+' • '+r['territory'].toString())),
    _list(_licenses,(r)=>(r['licensor'].toString()+' → '+r['licensee'].toString()),(r)=>(r['usage_type'].toString()+' • '+r['asset_type'].toString()+' '+r['asset_id'].toString()+' • '+r['territory'].toString())),
  ]);
}
