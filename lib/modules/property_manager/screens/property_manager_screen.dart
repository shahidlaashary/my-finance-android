import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/property_manager/services/property_manager_service.dart';

class PropertyManagerScreen extends StatefulWidget {
  const PropertyManagerScreen({super.key});
  @override
  State<PropertyManagerScreen> createState() => _PropertyManagerScreenState();
}
class _PropertyManagerScreenState extends State<PropertyManagerScreen> {
  int tab=0; bool loading=true;
  List<Map<String,dynamic>> properties=[], tenants=[], contracts=[];
  String tr(String s)=>appText(context,s,s);
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    setState(()=>loading=true);
    try { final v=await Future.wait([PropertyManagerService.properties(),PropertyManagerService.tenants(),PropertyManagerService.contracts()]);
      if(mounted)setState(() { properties=v[0]; tenants=v[1]; contracts=v[2]; loading=false; });
    } catch(e){if(mounted)setState(()=>loading=false);message(e.toString());}
  }
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}
  Widget field(TextEditingController c,String label,{bool requiredField=false,TextInputType? keyboard,int lines=1})=>TextFormField(controller:c,maxLines:lines,keyboardType:keyboard,validator:requiredField?(v)=>(v==null||v.trim().isEmpty)?tr('Required'):null:null,decoration:InputDecoration(labelText:tr(label),border:const OutlineInputBorder()));
  Future<String?> storeFile(PlatformFile file) async {
    if(file.path==null)return null;
    final root=await getApplicationDocumentsDirectory();
    final dir=Directory(p.join(root.path,'property_manager','documents')); await dir.create(recursive:true);
    final name='${DateTime.now().microsecondsSinceEpoch}_${p.basename(file.name)}';
    return (await File(file.path!).copy(p.join(dir.path,name))).path;
  }
  Future<void> addDocs(int id) async {
    final result=await FilePicker.platform.pickFiles(allowMultiple:true);
    if(result==null)return;
    for(final f in result.files){final path=await storeFile(f);if(path!=null)await PropertyManagerService.addDocument(propertyId:id,title:p.basenameWithoutExtension(f.name),fileName:f.name,filePath:path,mimeType:f.extension??'');}
    await load();
  }
  Future<void> propertyForm({Map<String,dynamic>? row}) async {
    final name=TextEditingController(text:row?['name']?.toString()??''),address=TextEditingController(text:row?['address']?.toString()??''),area=TextEditingController(text:row?['area']?.toString()??''),price=TextEditingController(text:(row?['purchase_price']??0).toString()),value=TextEditingController(text:(row?['current_value']??0).toString()),notes=TextEditingController(text:row?['notes']?.toString()??'');
    String type=row?['type']?.toString()??'House',ownership=row?['ownership']?.toString()??'Owned',status=row?['status']?.toString()??'Active';
    DateTime? date=DateTime.tryParse(row?['purchase_date']?.toString()??'');
    final key=GlobalKey<FormState>();
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(sheet)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:Container(height:MediaQuery.sizeOf(ctx).height*.88,padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:Theme.of(ctx).colorScheme.surface,borderRadius:const BorderRadius.vertical(top:Radius.circular(24))),child:Form(key:key,child:ListView(children:[
      Text(row==null?tr('Add Property'):tr('Edit Property'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      field(name,'Property Name',requiredField:true),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:type,decoration:InputDecoration(labelText:tr('Property Type'),border:const OutlineInputBorder()),items:['House','Shop','Flat','Plot','Office','Warehouse','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>type=v);}),
      const SizedBox(height:10),field(address,'Address / Location',lines:2),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:ownership,decoration:InputDecoration(labelText:tr('Ownership'),border:const OutlineInputBorder()),items:['Owned','Rented','Leased','Jointly Owned'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>ownership=v);}),
      const SizedBox(height:10),field(area,'Area & Unit'),const SizedBox(height:10),field(price,'Purchase Price',keyboard:TextInputType.number),
      ListTile(contentPadding:EdgeInsets.zero,title:Text(tr('Purchase Date')),subtitle:Text(date==null?tr('Select date'):MaterialLocalizations.of(ctx).formatMediumDate(date!)),trailing:const Icon(Icons.calendar_month),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:date??DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime(2100));if(d!=null)refresh(()=>date=d);}),
      field(value,'Current Value',keyboard:TextInputType.number),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:tr('Status'),border:const OutlineInputBorder()),items:['Active','Vacant','Rented','Sold','Archived'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>status=v);}),
      const SizedBox(height:10),field(notes,'Notes',lines:2),
      if(row!=null) ...[
        const SizedBox(height:18),Text(tr('Property Documents'),style:const TextStyle(fontWeight:FontWeight.bold)),
        FutureBuilder<List<Map<String,dynamic>>>(future:PropertyManagerService.documents(row['id'] as int),builder:(ctx,s)=>Column(children:(s.data??[]).map((d)=>ListTile(title:Text(d['title'].toString()),subtitle:Text(d['file_name'].toString()),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='delete')await PropertyManagerService.deleteDocument(d['id'] as int);if(v=='replace'){final pick=await FilePicker.platform.pickFiles();if(pick!=null&&pick.files.isNotEmpty){final f=pick.files.first,path=await storeFile(pick.files.first);if(path!=null)await PropertyManagerService.updateDocument(d['id'] as int,title:d['title'].toString(),fileName:f.name,filePath:path,mimeType:f.extension??'');}}refresh((){});},itemBuilder:(_)=>[PopupMenuItem(value:'replace',child:Text(tr('Replace'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))]))).toList())),
        OutlinedButton.icon(onPressed:()=>addDocs(row['id'] as int),icon:const Icon(Icons.attach_file),label:Text(tr('Add Documents'))),
      ] else Text(tr('You can attach multiple documents after saving this property.')),
      const SizedBox(height:18),FilledButton(onPressed:()async{if(!key.currentState!.validate())return;try{final id=await PropertyManagerService.saveProperty(id:row?['id'] as int?,name:name.text,type:type,address:address.text,ownership:ownership,area:area.text,purchasePrice:double.tryParse(price.text)??0,purchaseDate:date?.toIso8601String()??'',currentValue:double.tryParse(value.text)??0,status:status,notes:notes.text);if(sheet.mounted)Navigator.pop(sheet);if(row==null)await addDocs(id);await load();}catch(e){message(e.toString());}},child:Text(row==null?tr('Save Property'):tr('Update Property'))),
    ])))));
    for(final c in [name,address,area,price,value,notes]){c.dispose();}
  }
  Future<void> tenantForm({Map<String,dynamic>? row}) async {
    final n=TextEditingController(text:row?['name']?.toString()??''),p1=TextEditingController(text:row?['phone']?.toString()??''),e=TextEditingController(text:row?['email']?.toString()??''),identity=TextEditingController(text:row?['identity_number']?.toString()??''),notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(s).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(row==null?tr('Add Tenant'):tr('Edit Tenant'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      field(n,'Tenant Name',requiredField:true),const SizedBox(height:10),field(p1,'Phone'),const SizedBox(height:10),field(e,'Email'),const SizedBox(height:10),field(identity,'ID / Passport Number'),const SizedBox(height:10),field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertyManagerService.saveTenant(id:row?['id'] as int?,name:n.text,phone:p1.text,email:e.text,identityNumber:identity.text,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();}catch(err){message(err.toString());}},child:Text(tr('Save Tenant'))),
    ]))));
    for(final c in [n,p1,e,identity,notes]){c.dispose();}
  }
  Future<void> contractForm() async {
    if(properties.isEmpty||tenants.isEmpty){message(tr('Add a property and tenant first.'));return;}
    int propertyId=properties.first['id'] as int,tenantId=tenants.first['id'] as int;String kind='Rental',frequency='Monthly',status='Active';DateTime start=DateTime.now();DateTime? end;
    final rent=TextEditingController(),deposit=TextEditingController(),notes=TextEditingController();
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(tr('Add Contract'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      DropdownButtonFormField<int>(value:propertyId,decoration:InputDecoration(labelText:tr('Property'),border:const OutlineInputBorder()),items:properties.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text(v['name'].toString()))).toList(),onChanged:(v){if(v!=null)refresh(()=>propertyId=v);}),
      const SizedBox(height:10),DropdownButtonFormField<int>(value:tenantId,decoration:InputDecoration(labelText:tr('Tenant'),border:const OutlineInputBorder()),items:tenants.map((v)=>DropdownMenuItem(value:v['id'] as int,child:Text(v['name'].toString()))).toList(),onChanged:(v){if(v!=null)refresh(()=>tenantId=v);}),
      const SizedBox(height:10),DropdownButtonFormField<String>(value:kind,decoration:InputDecoration(labelText:tr('Contract Type'),border:const OutlineInputBorder()),items:['Rental','Lease','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>kind=v);}),
      ListTile(title:Text(tr('Start Date')),subtitle:Text(MaterialLocalizations.of(ctx).formatMediumDate(start)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:start,firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>start=d);}),
      ListTile(title:Text(tr('End Date')),subtitle:Text(end==null?tr('No end date'):MaterialLocalizations.of(ctx).formatMediumDate(end!)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:end??start,firstDate:start,lastDate:DateTime(2100));if(d!=null)refresh(()=>end=d);}),
      field(rent,'Rent Amount',keyboard:TextInputType.number),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:frequency,decoration:InputDecoration(labelText:tr('Payment Frequency'),border:const OutlineInputBorder()),items:['Monthly','Weekly','Quarterly','Yearly','One-time'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>frequency=v);}),
      const SizedBox(height:10),field(deposit,'Security Deposit',keyboard:TextInputType.number),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:tr('Status'),border:const OutlineInputBorder()),items:['Draft','Active','Expired','Terminated'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>status=v);}),
      const SizedBox(height:10),field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertyManagerService.saveContract(propertyId:propertyId,tenantId:tenantId,contractType:kind,startDate:start.toIso8601String(),endDate:end?.toIso8601String()??'',rent:double.tryParse(rent.text)??0,frequency:frequency,deposit:double.tryParse(deposit.text)??0,status:status,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();}catch(err){message(err.toString());}},child:Text(tr('Save Contract'))),
    ]))));
    rent.dispose();deposit.dispose();notes.dispose();
  }
  Future<void> showProperty(Map<String,dynamic> row) async {
    final docs=await PropertyManagerService.documents(row['id'] as int);if(!mounted)return;
    await showModalBottomSheet<void>(context:context,useSafeArea:true,builder:(s)=>Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(row['name'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('${row['type']} • ${row['ownership']}'),Text(row['address']?.toString()??''),Text('${tr('Current Value')}: ${row['current_value']}'),const Divider(),Text(tr('Documents'),style:const TextStyle(fontWeight:FontWeight.bold)),
      if(docs.isEmpty)Text(tr('No documents attached')) else ...docs.map((d)=>ListTile(title:Text(d['title'].toString()),subtitle:Text(d['file_name'].toString()),leading:const Icon(Icons.description_outlined),onTap:()async{final r=await OpenFilex.open(d['file_path'].toString());if(r.type!=ResultType.done)message(tr('Unable to open this document.'));})),
      Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:(){Navigator.pop(s);propertyForm(row:row);},icon:const Icon(Icons.edit),label:Text(tr('Edit Property')))),
    ])));
  }
  Future<void> plusMenu() async => showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(s)=>SafeArea(child:Wrap(children:[
    ListTile(leading:const Icon(Icons.home_work_outlined),title:Text(tr('Add Property')),onTap:(){Navigator.pop(s);propertyForm();}),
    ListTile(leading:const Icon(Icons.person_add_alt_1),title:Text(tr('Add Tenant')),onTap:(){Navigator.pop(s);tenantForm();}),
    ListTile(leading:const Icon(Icons.description_outlined),title:Text(tr('Add Contract')),onTap:(){Navigator.pop(s);contractForm();}),
  ])));
  Widget propertyTile(Map<String,dynamic> row)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.home_work_outlined)),title:Text(row['name'].toString()),subtitle:Text('${row['type']} • ${row['status']}'),trailing:const Icon(Icons.chevron_right),onTap:()=>showProperty(row)));
  Widget listing(List<Map<String,dynamic>> rows,String kind){
    if(rows.isEmpty)return Center(child:Text(tr('No records yet.')));
    return ListView.builder(padding:const EdgeInsets.all(12),itemCount:rows.length,itemBuilder:(ctx,i){final r=rows[i];
      if(kind=='Properties')return propertyTile(r);
      if(kind=='Tenants')return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person_outline)),title:Text(r['name'].toString()),subtitle:Text(r['phone']?.toString()??''),onTap:()=>tenantForm(row:r),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='delete'){try{await PropertyManagerService.deleteTenant(r['id'] as int);await load();}catch(e){message(e.toString());}}},itemBuilder:(_)=>[PopupMenuItem(value:'delete',child:Text(tr('Delete')))])));
      return Card(child:ListTile(leading:const Icon(Icons.description_outlined),title:Text(r['property_name']?.toString()??''),subtitle:Text('${r['tenant_name']} • ${r['contract_type']} • ${r['status']}'),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='delete'){await PropertyManagerService.deleteContract(r['id'] as int);await load();}},itemBuilder:(_)=>[PopupMenuItem(value:'delete',child:Text(tr('Delete')))])));
    });
  }
  Widget overview()=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.7,crossAxisSpacing:10,mainAxisSpacing:10,children:[
      stat('Properties',properties.length,Icons.home_work_outlined),stat('Tenants',tenants.length,Icons.people_outline),
      stat('Active Contracts',contracts.where((c)=>c['status']=='Active').length,Icons.description_outlined),
      stat('Vacant Properties',properties.where((p)=>p['status']=='Vacant').length,Icons.meeting_room_outlined),
    ]),const SizedBox(height:18),Text(tr('Recent Properties'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    if(properties.isEmpty)Text(tr('No properties added yet.')) else ...properties.take(5).map(propertyTile),
  ]));
  Widget stat(String title,int n,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:7),Text('$n',style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold)),Text(tr(title),maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall)])));
  Widget nav(int i,IconData icon,String label){final selected=tab==i;return Expanded(child:InkWell(onTap:()=>setState(()=>tab=i),child:SizedBox(height:66,child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:22,color:selected?Theme.of(context).colorScheme.primary:Theme.of(context).hintColor),const SizedBox(height:2),Text(tr(label),style:TextStyle(fontSize:10,fontWeight:FontWeight.w600,color:selected?Theme.of(context).colorScheme.primary:Theme.of(context).hintColor))]))));}
  @override Widget build(BuildContext context){
    final pages=[overview(),listing(properties,'Properties'),listing(tenants,'Tenants'),listing(contracts,'Contracts')];
    return Scaffold(appBar:AppBar(title:Text(tr('Property Manager')),actions:[IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):IndexedStack(index:tab,children:pages),
      bottomNavigationBar:Container(color:Theme.of(context).colorScheme.surface,child:SafeArea(top:false,child:SizedBox(height:66,child:Row(children:[
        nav(0,Icons.dashboard_outlined,'Overview'),nav(1,Icons.home_work_outlined,'Properties'),
        Expanded(child:InkWell(onTap:plusMenu,child:Center(child:Container(width:43,height:43,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary,borderRadius:BorderRadius.circular(15)),child:Icon(Icons.add_rounded,color:Theme.of(context).colorScheme.onPrimary,size:29))))),
        nav(2,Icons.people_outline,'Tenants'),nav(3,Icons.description_outlined,'Contracts'),
      ])))),
    );
  }
}
