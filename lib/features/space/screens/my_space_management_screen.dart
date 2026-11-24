import 'package:flutter/material.dart';
import 'package:my_finance/features/space/services/my_space_service.dart';
import 'package:my_finance/features/space/screens/agreement_templates_screen.dart';
import 'package:my_finance/features/recycle_bin/screens/recycle_bin_screen.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});
  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> with SingleTickerProviderStateMixin {
  final _service = MySpaceService.instance;
  late final TabController _tabs;
  Future<List<Map<String, Object?>>>? _companies, _manageLabels, _manageArtists;
  @override
  void initState() { super.initState(); _tabs = TabController(length: 5, vsync: this); _refreshManagementData(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }
  void _refreshManagementData() { _companies = _service.getAgreementCompanies(); _manageLabels = _service.getAgreementLabels(); _manageArtists = _service.getArtists(); }
  Future<String?> _nameDialog(String title, {String initial = '', String label = 'Name'}) async {
    final c = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title), content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save'))],
    ));
    c.dispose(); return result?.trim().isEmpty == true ? null : result?.trim();
  }
  Future<void> _manageCompany([Map<String,Object?>? row]) async {
    final name = await _nameDialog(row == null ? 'Create Company' : 'Edit Company', initial: row?['name']?.toString() ?? '', label: 'Company Name');
    if (name == null) return;
    try { if(row == null) { await _service.createAgreementCompany(name); } else { await _service.updateAgreementCompany(row['id'] as int, name); } setState(_refreshManagementData); }
    catch(e) { _message(e.toString()); }
  }
  Future<void> _manageLabel([Map<String,Object?>? row]) async {
    final companies = await _service.getAgreementCompanies();
    if (!mounted) return;
    if(companies.isEmpty) { _message('Create a company first.'); return; }
    int companyId = (row?['company_id'] as int?) ?? (companies.first['id'] as int);
    final name = TextEditingController(text: row?['name']?.toString() ?? '');
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, refresh) => AlertDialog(
      title: Text(row == null ? 'Create Label' : 'Edit Label'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(value: companyId, decoration: const InputDecoration(labelText: 'Company'), items: companies.map((c)=>DropdownMenuItem(value:c['id'] as int,child:Text(c['name'].toString()))).toList(), onChanged:(v){if(v!=null)refresh(()=>companyId=v);}),
        const SizedBox(height:12), TextField(controller:name,decoration:const InputDecoration(labelText:'Label Name',border:OutlineInputBorder())),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    )));
    if(saved==true && name.text.trim().isNotEmpty) {
      try { if(row==null) { await _service.createAgreementLabel(companyId:companyId,name:name.text); } else { await _service.updateAgreementLabel(id:row['id'] as int,companyId:companyId,name:name.text); } setState(_refreshManagementData); }
      catch(e){_message(e.toString());}
    }
    name.dispose();
  }
  Future<void> _manageArtist([Map<String,Object?>? row]) async {
    final fields = ['name','stage_name','phone','email','genre','notes'];
    final labels = ['Artist Name','Stage Name','Phone','Email','Genre','Notes'];
    final controllers = {for(var i=0;i<fields.length;i++) fields[i]:TextEditingController(text:row?[fields[i]]?.toString()??'')};
    final saved = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(row==null?'Add Artist':'Edit Artist'),
      content:SizedBox(width:480,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(var i=0;i<fields.length;i++) Padding(padding:const EdgeInsets.only(bottom:10),child:TextField(controller:controllers[fields[i]],maxLines:fields[i]=='notes'?3:1,decoration:InputDecoration(labelText:labels[i],border:const OutlineInputBorder()))),
      ]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save Artist'))],
    ));
    if(saved==true && controllers['name']!.text.trim().isNotEmpty){
      await _service.saveArtist({'id':row?['id'],for(final f in fields) f:controllers[f]!.text});
      if(mounted)setState(_refreshManagementData);
    }
    for(final c in controllers.values){c.dispose();}
  }
  void _message(String value){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(value)));}
  Future<void> _deleteManagementItem(String title, Future<void> Function() action) async {
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Delete $title?'),content:const Text('This item will be removed from My Space management.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
    if(yes==true){await action();if(mounted)setState(_refreshManagementData);}
  }
  Widget _buildManagementList(Future<List<Map<String,Object?>>>? future,{required String empty,required Widget Function(Map<String,Object?>) tile}) => FutureBuilder<List<Map<String,Object?>>>(future:future,builder:(ctx,s){if(s.connectionState==ConnectionState.waiting)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('Unable to load: ${s.error}'));final rows=s.data??[];if(rows.isEmpty)return Center(child:Text(empty));return ListView(padding:const EdgeInsets.all(12),children:rows.map(tile).toList());});
  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Management'),bottom:TabBar(controller:_tabs,isScrollable:true,tabs:const[Tab(text:'Companies'),Tab(text:'Labels'),Tab(text:'Artists'),Tab(text:'Templates'),Tab(text:'Trash')])),
    body:TabBarView(controller:_tabs,children:[
      _buildManagementList(_companies,empty:'No companies yet',tile:(r)=>Card(child:ListTile(leading:const Icon(Icons.business_outlined),title:Text(r['name'].toString()),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_manageCompany(r);if(v=='delete')_deleteManagementItem('company',()=>_service.deleteAgreementCompany(r['id'] as int));},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))])))),
      _buildManagementList(_manageLabels,empty:'No labels yet',tile:(r)=>Card(child:ListTile(leading:const Icon(Icons.label_outline),title:Text(r['name'].toString()),subtitle:Text(r['company_name']?.toString()??''),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_manageLabel(r);if(v=='delete')_deleteManagementItem('label',()=>_service.deleteAgreementLabel(r['id'] as int));},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))])))),
      _buildManagementList(_manageArtists,empty:'No artists yet',tile:(r)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.mic_none)),title:Text(r['name'].toString()),subtitle:Text([r['stage_name'],r['genre'],r['phone']].where((x)=>x!=null&&x.toString().isNotEmpty).join(' • ')),onTap:()=>_manageArtist(r),trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_manageArtist(r);if(v=='delete')_deleteManagementItem('artist',()=>_service.deleteArtist(r['id'] as int));},itemBuilder:(_)=>const[PopupMenuItem(value:'edit',child:Text('Edit')),PopupMenuItem(value:'delete',child:Text('Delete'))])))),
      const AgreementTemplatesScreen(),
      const RecycleBinScreen(),
    ]),
    floatingActionButton:AnimatedBuilder(animation:_tabs,builder:(ctx,_){
      if(_tabs.index>=3)return const SizedBox.shrink();
      final actions=[_manageCompany,_manageLabel,_manageArtist];
      return FloatingActionButton.extended(onPressed:()=>actions[_tabs.index](),icon:const Icon(Icons.add),label:Text(['Add Company','Add Label','Add Artist'][_tabs.index]));
    }),
  );
}
