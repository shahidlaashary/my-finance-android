import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:my_finance/core/services/file_storage_service.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/modules/properties/services/properties_service.dart';
import 'package:my_finance/modules/finance/services/currency_service.dart';
import 'package:my_finance/features/notifications/services/reminder_service.dart';

class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({super.key});
  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}
class _PropertiesScreenState extends State<PropertiesScreen> {
  int tab=0; bool loading=true;
  List<Map<String,dynamic>> properties=[], tenants=[], contracts=[], owners=[], rentPayments=[], maintenanceItems=[], reportRows=[];
  String reportCurrency='PKR';
  DateTimeRange? reportRange;
  String _dateKey(DateTime date)=>'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
  String tr(String s)=>appText(context,s,s);
  @override void initState(){super.initState();load();}
  Future<void> load() async {
    setState(()=>loading=true);
    try { await PropertiesService.generateScheduledRentPayments(); final v=await Future.wait([PropertiesService.properties(),PropertiesService.tenants(),PropertiesService.contracts(),PropertiesService.owners(),PropertiesService.rentPayments(),PropertiesService.maintenance(),PropertiesService.financialReport(fromDate:reportRange==null?null:_dateKey(reportRange!.start),toDate:reportRange==null?null:_dateKey(reportRange!.end))]);
      final baseCurrency=await CurrencyService.getBaseCurrency();
      try { await _syncPropertyReminders(contracts:v[2],payments:v[4],maintenance:v[5]); } catch (_) { /* Reminder permission/service errors must not block Properties data. */ }
      if(mounted)setState(() { properties=v[0]; tenants=v[1]; contracts=v[2]; owners=v[3]; rentPayments=v[4]; maintenanceItems=v[5]; reportRows=v[6]; reportCurrency=baseCurrency; loading=false; });
    } catch(e){if(mounted)setState(()=>loading=false);message(e.toString());}
  }
  void message(String s){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}

  DateTime? _reminderAt(String? raw,{int daysBefore=0}) {
    if(raw==null||raw.isEmpty)return null;
    final parsed=DateTime.tryParse(raw);
    if(parsed==null)return null;
    final date=DateTime(parsed.year,parsed.month,parsed.day).subtract(Duration(days:daysBefore));
    return DateTime(date.year,date.month,date.day,9);
  }

  Future<void> _syncPropertyReminders({
    required List<Map<String,dynamic>> contracts,
    required List<Map<String,dynamic>> payments,
    required List<Map<String,dynamic>> maintenance,
  }) async {
    final now=DateTime.now();
    final desired=<Map<String,dynamic>>[];
    for(final payment in payments) {
      if(payment['status']=='Paid')continue;
      final due=_reminderAt(payment['due_date']?.toString());
      if(due==null)continue;
      desired.add({
        'source_key':'properties:rent:${payment['id']}',
        'title':'Rent payment due',
        'note':'${payment['property_name']??'Property'} • Due ${payment['due_date']} • Amount ${payment['amount_due']}',
        'category':'Property Rent','when':due,
      });
    }
    for(final contract in contracts) {
      if(contract['status']!='Active')continue;
      final rawEnd=contract['end_date']?.toString()??'';
      final expiry=DateTime.tryParse(rawEnd);
      if(expiry==null||rawEnd.isEmpty)continue;
      final expiryDate=DateTime(expiry.year,expiry.month,expiry.day);
      if(!expiryDate.isAfter(DateTime(now.year,now.month,now.day)))continue;
      var reminder=_reminderAt(rawEnd,daysBefore:7)!;
      if(!reminder.isAfter(now))reminder=now.add(const Duration(minutes:2));
      desired.add({
        'source_key':'properties:contract:${contract['id']}',
        'title':'Property contract ending soon',
        'note':'${contract['property_name']??'Property'} • ${contract['tenant_name']??'Tenant'} • Ends $rawEnd',
        'category':'Property Contract','when':reminder,
      });
    }
    for(final item in maintenance) {
      if(item['status']=='Completed'||item['status']=='Cancelled')continue;
      final due=_reminderAt(item['due_date']?.toString());
      if(due==null)continue;
      desired.add({
        'source_key':'properties:maintenance:${item['id']}',
        'title':'Maintenance due',
        'note':'${item['property_name']??'Property'} • ${item['title']} • Priority ${item['priority']}',
        'category':'Property Maintenance','when':due,
      });
    }
    await ReminderService.instance.syncLinkedReminders(
      sourcePrefix:'properties:',desired:desired,
    );
  }


  Widget field(TextEditingController c,String label,{bool requiredField=false,TextInputType? keyboard,int lines=1})=>TextFormField(controller:c,maxLines:lines,keyboardType:keyboard,validator:requiredField?(v)=>(v==null||v.trim().isEmpty)?tr('Required'):null:null,decoration:InputDecoration(labelText:tr(label),border:const OutlineInputBorder()));
  Future<void> addDocs(int id) async {
    final result=await FilePicker.platform.pickFiles(allowMultiple:true);
    if(result==null)return;
    for(final f in result.files){final path=await FileStorageService.storePickedFile(f,directory:'properties/documents');if(path!=null)await PropertiesService.addDocument(propertyId:id,title:p.basenameWithoutExtension(f.name),fileName:f.name,filePath:path,mimeType:f.extension??'');}
    await load();
  }
  Future<void> propertyForm({Map<String,dynamic>? row}) async {
    final name=TextEditingController(text:row?['name']?.toString()??''),address=TextEditingController(text:row?['address']?.toString()??''),area=TextEditingController(text:row?['area']?.toString()??''),price=TextEditingController(text:(row?['purchase_price']??0).toString()),value=TextEditingController(text:(row?['current_value']??0).toString()),notes=TextEditingController(text:row?['notes']?.toString()??'');
    String type=row?['type']?.toString()??'House',ownership=row?['ownership']?.toString()??'Owned',status=row?['status']?.toString()??'Active';
    DateTime? date=DateTime.tryParse(row?['purchase_date']?.toString()??'');
    final List<PlatformFile> newDocs=[];
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
        FutureBuilder<List<Map<String,dynamic>>>(future:PropertiesService.documents(row['id'] as int),builder:(ctx,s)=>Column(children:(s.data??[]).map((d)=>ListTile(title:Text(d['title'].toString()),subtitle:Text(d['file_name'].toString()),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='delete')await PropertiesService.deleteDocument(d['id'] as int);if(v=='edit'){final title=TextEditingController(text:d['title'].toString());final ok=await showDialog<bool>(context:ctx,builder:(dialog)=>AlertDialog(title:Text(tr('Edit Document Name')),content:TextField(controller:title,decoration:InputDecoration(labelText:tr('Document Name'))),actions:[TextButton(onPressed:()=>Navigator.pop(dialog,false),child:Text(tr('Cancel'))),FilledButton(onPressed:()=>Navigator.pop(dialog,true),child:Text(tr('Save')))]));if(ok==true&&title.text.trim().isNotEmpty)await PropertiesService.updateDocument(d['id'] as int,title:title.text);title.dispose();}if(v=='replace'){final pick=await FilePicker.platform.pickFiles();if(pick!=null&&pick.files.isNotEmpty){final f=pick.files.first,path=await FileStorageService.storePickedFile(pick.files.first,directory:'properties/documents');if(path!=null)await PropertiesService.updateDocument(d['id'] as int,title:d['title'].toString(),fileName:f.name,filePath:path,mimeType:f.extension??'');}}refresh((){});},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Edit'))),PopupMenuItem(value:'replace',child:Text(tr('Replace'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))]))).toList())),
        OutlinedButton.icon(onPressed:()=>addDocs(row['id'] as int),icon:const Icon(Icons.attach_file),label:Text(tr('Add Documents'))),
      ] else ...[
        OutlinedButton.icon(onPressed:()async{final picked=await FilePicker.platform.pickFiles(allowMultiple:true);if(picked!=null)refresh(()=>newDocs.addAll(picked.files));},icon:const Icon(Icons.attach_file),label:Text(tr('Attach Documents'))),
        ...newDocs.asMap().entries.map((entry)=>ListTile(dense:true,title:Text(entry.value.name),trailing:IconButton(icon:const Icon(Icons.close),onPressed:()=>refresh(()=>newDocs.removeAt(entry.key))))),
      ],
      const SizedBox(height:18),FilledButton(onPressed:()async{if(!key.currentState!.validate())return;try{final id=await PropertiesService.saveProperty(id:row?['id'] as int?,name:name.text,type:type,address:address.text,ownership:ownership,area:area.text,purchasePrice:double.tryParse(price.text)??0,purchaseDate:date?.toIso8601String()??'',currentValue:double.tryParse(value.text)??0,status:status,notes:notes.text);if(row==null){for(final file in newDocs){final path=await FileStorageService.storePickedFile(file,directory:'properties/documents');if(path!=null)await PropertiesService.addDocument(propertyId:id,title:p.basenameWithoutExtension(file.name),fileName:file.name,filePath:path,mimeType:file.extension??'');}}if(sheet.mounted)Navigator.pop(sheet);await load();}catch(e){message(e.toString());}},child:Text(row==null?tr('Save Property'):tr('Update Property'))),
    ]))))));
    for(final c in [name,address,area,price,value,notes]){c.dispose();}
  }
  Future<void> tenantForm({Map<String,dynamic>? row}) async {
    final n=TextEditingController(text:row?['name']?.toString()??''),p1=TextEditingController(text:row?['phone']?.toString()??''),e=TextEditingController(text:row?['email']?.toString()??''),identity=TextEditingController(text:row?['identity_number']?.toString()??''),notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(s).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(row==null?tr('Add Tenant'):tr('Edit Tenant'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      field(n,'Tenant Name',requiredField:true),const SizedBox(height:10),field(p1,'Phone'),const SizedBox(height:10),field(e,'Email'),const SizedBox(height:10),field(identity,'ID / Passport Number'),const SizedBox(height:10),field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertiesService.saveTenant(id:row?['id'] as int?,name:n.text,phone:p1.text,email:e.text,identityNumber:identity.text,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();}catch(err){message(err.toString());}},child:Text(tr('Save Tenant'))),
    ]))));
    for(final c in [n,p1,e,identity,notes]){c.dispose();}
  }

  Future<void> ownerForm({Map<String,dynamic>? row}) async {
    final n=TextEditingController(text:row?['name']?.toString()??''),phone=TextEditingController(text:row?['phone']?.toString()??''),email=TextEditingController(text:row?['email']?.toString()??''),identity=TextEditingController(text:row?['identity_number']?.toString()??''),address=TextEditingController(text:row?['address']?.toString()??''),notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(s).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(tr(row==null?'Add Owner':'Edit Owner'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      field(n,'Owner Name',requiredField:true),const SizedBox(height:10),field(phone,'Phone'),const SizedBox(height:10),field(email,'Email'),const SizedBox(height:10),field(identity,'ID / Passport Number'),const SizedBox(height:10),field(address,'Address',lines:2),const SizedBox(height:10),field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertiesService.saveOwner(id:row?['id'] as int?,name:n.text,phone:phone.text,email:email.text,identityNumber:identity.text,address:address.text,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();}catch(e){message(e.toString());}},child:Text(tr(row==null?'Save Owner':'Update Owner'))),
    ]))));
    for(final c in [n,phone,email,identity,address,notes]){c.dispose();}
  }



  Future<void> maintenanceForm({Map<String,dynamic>? row}) async {
    if(properties.isEmpty){message(tr('Add a property first.'));return;}
    int propertyId=(row?['property_id'] as int?)??(properties.first['id'] as int);
    String category=row?['category']?.toString()??'General',priority=row?['priority']?.toString()??'Medium',status=row?['status']?.toString()??'Open';
    DateTime? due=DateTime.tryParse(row?['due_date']?.toString()??''),completed=DateTime.tryParse(row?['completed_date']?.toString()??'');
    String photoPath=row?['photo_path']?.toString()??'';
    final originalPhotoPath=photoPath;
    final title=TextEditingController(text:row?['title']?.toString()??''),description=TextEditingController(text:row?['description']?.toString()??''),assigned=TextEditingController(text:row?['assigned_to']?.toString()??''),estimated=TextEditingController(text:(row?['estimated_cost']??0).toString()),actual=TextEditingController(text:(row?['actual_cost']??0).toString());
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(sheet)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SizedBox(height:MediaQuery.sizeOf(ctx).height*.88,child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[
      Text(tr(row==null?'Add Maintenance':'Edit Maintenance'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:12),
      Expanded(child:ListView(children:[
        DropdownButtonFormField<int>(value:propertyId,decoration:InputDecoration(labelText:tr('Property'),border:const OutlineInputBorder()),items:properties.map((p)=>DropdownMenuItem(value:p['id'] as int,child:Text(p['name'].toString()))).toList(),onChanged:(v){if(v!=null)refresh(()=>propertyId=v);}),
        const SizedBox(height:10),field(title,'Maintenance Title',requiredField:true),const SizedBox(height:10),field(description,'Description',lines:3),const SizedBox(height:10),
        DropdownButtonFormField<String>(value:category,decoration:InputDecoration(labelText:tr('Category'),border:const OutlineInputBorder()),items:['General','Plumbing','Electrical','Painting','Cleaning','Appliance','Structural','Other'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>category=v);}),
        const SizedBox(height:10),DropdownButtonFormField<String>(value:priority,decoration:InputDecoration(labelText:tr('Priority'),border:const OutlineInputBorder()),items:['Low','Medium','High','Urgent'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>priority=v);}),
        const SizedBox(height:10),field(assigned,'Assigned To'),const SizedBox(height:10),field(estimated,'Estimated Cost',keyboard:const TextInputType.numberWithOptions(decimal:true)),const SizedBox(height:10),field(actual,'Actual Cost',keyboard:const TextInputType.numberWithOptions(decimal:true)),const SizedBox(height:10),
        DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:tr('Status'),border:const OutlineInputBorder()),items:['Open','In Progress','On Hold','Completed','Cancelled'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>status=v);}),
        ListTile(contentPadding:EdgeInsets.zero,title:Text(tr('Due Date')),subtitle:Text(due==null?tr('Not set'):MaterialLocalizations.of(ctx).formatMediumDate(due!)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:due??DateTime.now(),firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>due=d);}),
        if(status=='Completed')ListTile(contentPadding:EdgeInsets.zero,title:Text(tr('Completed Date')),subtitle:Text(completed==null?tr('Not set'):MaterialLocalizations.of(ctx).formatMediumDate(completed!)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:completed??DateTime.now(),firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>completed=d);}),
        OutlinedButton.icon(onPressed:()async{final pick=await FilePicker.platform.pickFiles(type:FileType.image);if(pick!=null&&pick.files.isNotEmpty){final stored=await FileStorageService.storePickedFile(pick.files.first,directory:'properties/maintenance');if(stored!=null)refresh(()=>photoPath=stored);}},icon:const Icon(Icons.photo_outlined),label:Text(tr(photoPath.isEmpty?'Attach Photo':'Replace Photo'))),
        if(photoPath.isNotEmpty)Row(children:[Expanded(child:Text(tr('Maintenance photo attached'))),TextButton(onPressed:()=>refresh(()=>photoPath=''),child:Text(tr('Remove Photo')))]),
      ])),
      SizedBox(width:double.infinity,child:FilledButton(onPressed:()async{try{await PropertiesService.saveMaintenance(id:row?['id'] as int?,propertyId:propertyId,title:title.text,description:description.text,category:category,priority:priority,assignedTo:assigned.text,estimatedCost:double.tryParse(estimated.text)??0,actualCost:double.tryParse(actual.text)??0,status:status,dueDate:due?.toIso8601String()??'',completedDate:status=='Completed'?(completed??DateTime.now()).toIso8601String():'',photoPath:photoPath);if(originalPhotoPath.isNotEmpty&&originalPhotoPath!=photoPath){try{await FileStorageService.deleteStoredFile(originalPhotoPath);}catch(_){}}if(sheet.mounted)Navigator.pop(sheet);await load();}catch(e){message(e.toString());}},child:Text(tr(row==null?'Save Maintenance':'Update Maintenance')))),
    ]))))));
    for(final c in [title,description,assigned,estimated,actual]){c.dispose();}
  }

  Future<void> rentScheduleForm(Map<String,dynamic> contract,{Map<String,dynamic>? row}) async {
    DateTime start=DateTime.tryParse(row?['start_date']?.toString()??'')??DateTime.now();
    DateTime next=DateTime.tryParse(row?['next_due_date']?.toString()??'')??start;
    DateTime? end=DateTime.tryParse(row?['end_date']?.toString()??'');
    String frequency=row?['frequency']?.toString()??'Monthly';
    String status=row?['status']?.toString()??'Active';
    final amount=TextEditingController(text:row?['amount']?.toString()??contract['rent']?.toString()??'');
    final notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(tr(row==null?'Create Rent Schedule':'Edit Rent Schedule'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      field(amount,'Rent Amount',keyboard:TextInputType.number),const SizedBox(height:10),
      DropdownButtonFormField<String>(value:frequency,decoration:InputDecoration(labelText:tr('Frequency'),border:const OutlineInputBorder()),items:['Weekly','Monthly','Quarterly','Yearly','One-time'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>frequency=v);}),
      ListTile(title:Text(tr('Start Date')),subtitle:Text(MaterialLocalizations.of(ctx).formatMediumDate(start)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:start,firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>start=d);}),
      ListTile(title:Text(tr('End Date')),subtitle:Text(end==null?tr('No end date'):MaterialLocalizations.of(ctx).formatMediumDate(end!)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:end??start,firstDate:start,lastDate:DateTime(2100));if(d!=null)refresh(()=>end=d);}),
      ListTile(title:Text(tr('Next Due Date')),subtitle:Text(MaterialLocalizations.of(ctx).formatMediumDate(next)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:next,firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>next=d);}),
      if(row!=null)DropdownButtonFormField<String>(value:status,decoration:InputDecoration(labelText:tr('Status'),border:const OutlineInputBorder()),items:['Active','Paused','Completed'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)refresh(()=>status=v);}),
      field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertiesService.saveRentSchedule(id:row?['id'] as int?,contractId:contract['id'] as int,amount:double.parse(amount.text),frequency:frequency,startDate:start.toIso8601String(),endDate:end?.toIso8601String()??'',nextDueDate:next.toIso8601String(),status:status,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();message(tr(row==null?'Rent schedule saved.':'Rent schedule updated.'));}catch(e){message(e.toString());}},child:Text(tr(row==null?'Save Schedule':'Update Schedule'))),
    ])))));
    amount.dispose();notes.dispose();
  }


  Future<void> rentRecordsSheet(Map<String,dynamic> contract) async {
    final schedules=await PropertiesService.rentSchedules(contractId:contract['id'] as int);
    final payments=await PropertiesService.rentPayments(contractId:contract['id'] as int);
    if(!mounted)return;
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>SizedBox(height:MediaQuery.sizeOf(s).height*.78,child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(tr('Rent Records'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      Text('${contract['property_name']} • ${contract['tenant_name']}'),
      const SizedBox(height:12),
      Expanded(child:ListView(children:[
        Text(tr('Schedules'),style:const TextStyle(fontWeight:FontWeight.bold)),
        if(schedules.isEmpty)Text(tr('No rent schedules yet.')) else ...schedules.map((r)=>ListTile(
          leading:const Icon(Icons.event_repeat),
          title:Text('${r['amount']} • ${r['frequency']}'),
          subtitle:Text('${r['status']} • Next due: ${r['next_due_date']}'),
          trailing:PopupMenuButton<String>(onSelected:(v)async{
            if(v=='edit'){Navigator.pop(s);await rentScheduleForm(contract,row:r);}
            if(v=='delete'){try{await PropertiesService.deleteRentSchedule(r['id'] as int);await load();if(s.mounted)Navigator.pop(s);message(tr('Schedule deleted. Payment history retained.'));}catch(e){message(e.toString());}}
          },itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Edit'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))]),
        )),
        const Divider(),Text(tr('Payments'),style:const TextStyle(fontWeight:FontWeight.bold)),
        if(payments.isEmpty)Text(tr('No rent payments recorded.')) else ...payments.map((r)=>ListTile(
          leading:Icon(r['status']=='Paid'?Icons.check_circle_outline:r['status']=='Overdue'?Icons.warning_amber:Icons.schedule),
          title:Text('${r['amount_paid']} / ${r['amount_due']}'),
          subtitle:Text('${r['status']} • Due: ${r['due_date']}'),
          trailing:PopupMenuButton<String>(onSelected:(v)async{
            if(v=='edit'){Navigator.pop(s);await rentPaymentForm(contract,row:r);}
            if(v=='delete'){try{await PropertiesService.deleteRentPayment(r['id'] as int);await load();if(s.mounted)Navigator.pop(s);message(tr('Rent payment deleted.'));}catch(e){message(e.toString());}}
          },itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Edit'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))]),
        )),
      ])),
      Row(children:[Expanded(child:OutlinedButton.icon(onPressed:(){Navigator.pop(s);rentScheduleForm(contract);},icon:const Icon(Icons.event_repeat),label:Text(tr('Schedule')))),const SizedBox(width:8),Expanded(child:FilledButton.icon(onPressed:(){Navigator.pop(s);rentPaymentForm(contract);},icon:const Icon(Icons.payments_outlined),label:Text(tr('Record Payment'))))]),
    ]))));
  }

  Future<void> rentPaymentForm(Map<String,dynamic> contract,{Map<String,dynamic>? row}) async {
    DateTime due=DateTime.tryParse(row?['due_date']?.toString()??'')??DateTime.now();
    DateTime paid=DateTime.tryParse(row?['paid_date']?.toString()??'')??DateTime.now();
    final dueAmount=TextEditingController(text:row?['amount_due']?.toString()??contract['rent']?.toString()??'');
    final paidAmount=TextEditingController(text:row?['amount_paid']?.toString()??'0');
    final method=TextEditingController(text:row?['payment_method']?.toString()??'');
    final reference=TextEditingController(text:row?['reference']?.toString()??'');
    final notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(tr(row==null?'Record Rent Payment':'Edit Rent Payment'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
      ListTile(title:Text(tr('Due Date')),subtitle:Text(MaterialLocalizations.of(ctx).formatMediumDate(due)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:due,firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>due=d);}),
      field(dueAmount,'Amount Due',keyboard:TextInputType.number),const SizedBox(height:10),field(paidAmount,'Amount Paid',keyboard:TextInputType.number),const SizedBox(height:10),
      ListTile(title:Text(tr('Paid Date')),subtitle:Text(MaterialLocalizations.of(ctx).formatMediumDate(paid)),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:paid,firstDate:DateTime(1990),lastDate:DateTime(2100));if(d!=null)refresh(()=>paid=d);}),
      field(method,'Payment Method'),const SizedBox(height:10),field(reference,'Reference / Cheque Number'),const SizedBox(height:10),field(notes,'Notes',lines:2),const SizedBox(height:16),
      FilledButton(onPressed:()async{try{await PropertiesService.saveRentPayment(id:row?['id'] as int?,contractId:contract['id'] as int,scheduleId:row?['schedule_id'] as int?,dueDate:due.toIso8601String(),amountDue:double.parse(dueAmount.text),amountPaid:double.parse(paidAmount.text),paidDate:double.parse(paidAmount.text)>0?paid.toIso8601String():'',paymentMethod:method.text,reference:reference.text,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();message(tr(row==null?'Rent payment saved.':'Rent payment updated.'));}catch(e){message(e.toString());}},child:Text(tr(row==null?'Save Payment':'Update Payment'))),
    ])))));
    for(final c in [dueAmount,paidAmount,method,reference,notes]){c.dispose();}
  }

  Future<void> contractForm({Map<String,dynamic>? row}) async {
    if(properties.isEmpty||tenants.isEmpty){message(tr('Add a property and tenant first.'));return;}
    int propertyId=(row?['property_id'] as int?)??(properties.first['id'] as int),tenantId=(row?['tenant_id'] as int?)??(tenants.first['id'] as int);String kind=row?['contract_type']?.toString()??'Rental',frequency=row?['frequency']?.toString()??'Monthly',status=row?['status']?.toString()??'Active';DateTime start=DateTime.tryParse(row?['start_date']?.toString()??'')??DateTime.now();DateTime? end=DateTime.tryParse(row?['end_date']?.toString()??'');
    final rent=TextEditingController(text:row?['rent']?.toString()??''),deposit=TextEditingController(text:row?['deposit']?.toString()??''),notes=TextEditingController(text:row?['notes']?.toString()??'');
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,useSafeArea:true,builder:(s)=>StatefulBuilder(builder:(ctx,refresh)=>Padding(padding:EdgeInsets.only(bottom:MediaQuery.viewInsetsOf(ctx).bottom),child:SingleChildScrollView(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,children:[
      Text(tr(row==null?'Add Contract':'Edit Contract'),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),const SizedBox(height:14),
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
      FilledButton(onPressed:()async{try{await PropertiesService.saveContract(id:row?['id'] as int?,propertyId:propertyId,tenantId:tenantId,contractType:kind,startDate:start.toIso8601String(),endDate:end?.toIso8601String()??'',rent:double.tryParse(rent.text)??0,frequency:frequency,deposit:double.tryParse(deposit.text)??0,status:status,notes:notes.text);if(s.mounted)Navigator.pop(s);await load();}catch(err){message(err.toString());}},child:Text(tr(row==null?'Save Contract':'Update Contract'))),
    ])))));
    rent.dispose();deposit.dispose();notes.dispose();
  }

  Future<void> linkOwnerForm(Map<String,dynamic> property) async {
    if(owners.isEmpty){message(tr('Add an owner first.'));return;}
    int ownerId=owners.first['id'] as int;
    final share=TextEditingController(text:'100');
    await showDialog<void>(context:context,builder:(dialog)=>AlertDialog(
      title:Text(tr('Link Owner')),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:ownerId,decoration:InputDecoration(labelText:tr('Owner')),items:owners.map((o)=>DropdownMenuItem(value:o['id'] as int,child:Text(o['name'].toString()))).toList(),onChanged:(v){if(v!=null)ownerId=v;}),
        const SizedBox(height:10),field(share,'Ownership Share (%)',keyboard:const TextInputType.numberWithOptions(decimal:true)),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(dialog),child:Text(tr('Cancel'))),FilledButton(onPressed:()async{try{await PropertiesService.linkOwner(propertyId:property['id'] as int,ownerId:ownerId,ownershipShare:double.parse(share.text));if(dialog.mounted)Navigator.pop(dialog);await load();message(tr('Owner linked.'));}catch(e){message(e.toString());}},child:Text(tr('Link')))],
    ));
    share.dispose();
  }

  Future<void> showProperty(Map<String,dynamic> row) async {
    final docs=await PropertiesService.documents(row['id'] as int);final linkedOwners=await PropertiesService.ownersForProperty(row['id'] as int);if(!mounted)return;
    await showModalBottomSheet<void>(context:context,useSafeArea:true,builder:(s)=>Padding(padding:const EdgeInsets.all(18),child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(row['name'].toString(),style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('${row['type']} • ${row['ownership']}'),Text(row['address']?.toString()??''),Text('${tr('Current Value')}: ${row['current_value']}'),const Divider(),Text(tr('Owners'),style:const TextStyle(fontWeight:FontWeight.bold)),if(linkedOwners.isEmpty)Text(tr('No owners linked')) else ...linkedOwners.map((o)=>ListTile(dense:true,title:Text(o['name'].toString()),subtitle:Text('${o['ownership_share']}%'),trailing:IconButton(icon:const Icon(Icons.link_off),onPressed:()async{await PropertiesService.unlinkOwner(o['link_id'] as int);if(s.mounted)Navigator.pop(s);await showProperty(row);},tooltip:tr('Unlink Owner')))),TextButton.icon(onPressed:()async{Navigator.pop(s);await linkOwnerForm(row);},icon:const Icon(Icons.person_add_alt_1),label:Text(tr('Link Owner'))),const Divider(),Text(tr('Documents'),style:const TextStyle(fontWeight:FontWeight.bold)),
      if(docs.isEmpty)Text(tr('No documents attached')) else ...docs.map((d)=>ListTile(title:Text(d['title'].toString()),subtitle:Text(d['file_name'].toString()),leading:const Icon(Icons.description_outlined),onTap:()async{final opened=await FileStorageService.openFile(d['file_path'].toString());if(!opened)message(tr('Unable to open this document.'));})),
      Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:(){Navigator.pop(s);propertyForm(row:row);},icon:const Icon(Icons.edit),label:Text(tr('Edit Property')))),
    ])));
  }
  Future<void> plusMenu() async => showModalBottomSheet<void>(context:context,showDragHandle:true,builder:(s)=>SafeArea(child:Wrap(children:[
    ListTile(leading:const Icon(Icons.home_work_outlined),title:Text(tr('Add Property')),onTap:(){Navigator.pop(s);propertyForm();}),
    ListTile(leading:const Icon(Icons.person_add_alt_1),title:Text(tr('Add Tenant')),onTap:(){Navigator.pop(s);tenantForm();}),
    ListTile(leading:const Icon(Icons.description_outlined),title:Text(tr('Add Contract')),onTap:(){Navigator.pop(s);contractForm();}),
    ListTile(leading:const Icon(Icons.person_outline),title:Text(tr('Add Owner')),onTap:(){Navigator.pop(s);ownerForm();}),
    ListTile(leading:const Icon(Icons.handyman_outlined),title:Text(tr('Add Maintenance')),onTap:(){Navigator.pop(s);maintenanceForm();}),
  ])));
  Widget propertyTile(Map<String,dynamic> row)=>Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.home_work_outlined)),title:Text(row['name'].toString()),subtitle:Text('${row['type']} • ${row['status']}'),trailing:const Icon(Icons.chevron_right),onTap:()=>showProperty(row)));
  Widget listing(List<Map<String,dynamic>> rows,String kind){
    if(rows.isEmpty)return Center(child:Text(tr('No records yet.')));
    return ListView.builder(padding:const EdgeInsets.all(12),itemCount:rows.length,itemBuilder:(ctx,i){final r=rows[i];
      if(kind=='Properties')return propertyTile(r);
      if(kind=='Tenants')return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.person_outline)),title:Text(r['name'].toString()),subtitle:Text(r['phone']?.toString()??''),onTap:()=>tenantForm(row:r),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='delete'){try{await PropertiesService.deleteTenant(r['id'] as int);await load();}catch(e){message(e.toString());}}},itemBuilder:(_)=>[PopupMenuItem(value:'delete',child:Text(tr('Delete')))])));
      if(kind=='Owners')return Card(child:ListTile(leading:const CircleAvatar(child:Icon(Icons.badge_outlined)),title:Text(r['name'].toString()),subtitle:Text(r['phone']?.toString()??''),onTap:()=>ownerForm(row:r),trailing:IconButton(icon:const Icon(Icons.edit_outlined),onPressed:()=>ownerForm(row:r))));
      if(kind=='Maintenance')return Card(child:ListTile(leading:CircleAvatar(child:Icon(r['priority']=='Urgent'||r['priority']=='High'?Icons.warning_amber:Icons.handyman_outlined)),title:Text(r['title'].toString()),subtitle:Text('${r['property_name']} • ${r['priority']} • ${r['status']}'),onTap:()=>maintenanceForm(row:r),trailing:Row(mainAxisSize:MainAxisSize.min,children:[if((r['photo_path']?.toString()??'').isNotEmpty)IconButton(icon:const Icon(Icons.photo_outlined),tooltip:tr('Open Photo'),onPressed:()async{final ok=await FileStorageService.openFile(r['photo_path'].toString());if(!ok)message(tr('Unable to open this photo.'));}),PopupMenuButton<String>(onSelected:(v)async{if(v=='edit')await maintenanceForm(row:r);if(v=='delete'){try{await PropertiesService.deleteMaintenance(r['id'] as int);final path=r['photo_path']?.toString()??'';if(path.isNotEmpty){try{await FileStorageService.deleteStoredFile(path);}catch(_){}}await load();}catch(e){message(e.toString());}}},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Edit'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))])])));
      return Card(child:ListTile(leading:const Icon(Icons.description_outlined),title:Text(r['property_name']?.toString()??''),subtitle:Text('${r['tenant_name']} • ${r['contract_type']} • ${r['status']}'),onTap:()=>contractForm(row:r),trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='edit'){contractForm(row:r);}if(v=='payment'){rentPaymentForm(r);}if(v=='schedule'){rentScheduleForm(r);}if(v=='records'){rentRecordsSheet(r);}if(v=='delete'){await PropertiesService.deleteContract(r['id'] as int);await load();}},itemBuilder:(_)=>[PopupMenuItem(value:'edit',child:Text(tr('Edit'))),PopupMenuItem(value:'payment',child:Text(tr('Record Rent Payment'))),PopupMenuItem(value:'schedule',child:Text(tr('Create Rent Schedule'))),PopupMenuItem(value:'records',child:Text(tr('View Rent Records'))),PopupMenuItem(value:'delete',child:Text(tr('Delete')))])));
    });
  }
  String reportAmount(Object? value) {
    final amount=(value as num?)?.toDouble()??0;
    return '$reportCurrency ${amount.toStringAsFixed(2)}';
  }
  Future<void> _chooseReportRange() async {
    final now=DateTime.now();
    final selected=await showDateRangePicker(context:context,firstDate:DateTime(1990),lastDate:DateTime(now.year+20),initialDateRange:reportRange);
    if(selected==null)return;
    setState(()=>reportRange=selected);
    await load();
  }
  Widget reports() {
    final rent=reportRows.fold<double>(0,(sum,row)=>sum+((row['rent_received'] as num?)?.toDouble()??0));
    final maintenance=reportRows.fold<double>(0,(sum,row)=>sum+((row['maintenance_expense'] as num?)?.toDouble()??0));
    final occupied=reportRows.where((row)=>(row['active_contract_count'] as num? ?? 0)>0).length;
    final vacant=reportRows.length-occupied;
    return RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
      Text(tr('Portfolio Financial Report'),style:const TextStyle(fontSize:19,fontWeight:FontWeight.bold)),
      Text(tr('Amounts are shown in the current app base currency: $reportCurrency')),
      Card(child:ListTile(leading:const Icon(Icons.date_range_outlined),title:Text(reportRange==null?tr('All dates'):'${MaterialLocalizations.of(context).formatMediumDate(reportRange!.start)} – ${MaterialLocalizations.of(context).formatMediumDate(reportRange!.end)}'),subtitle:Text(tr('Report Period')),onTap:_chooseReportRange,trailing:reportRange==null?const Icon(Icons.edit_calendar_outlined):IconButton(tooltip:tr('Clear date filter'),icon:const Icon(Icons.clear),onPressed:()async{setState(()=>reportRange=null);await load();}))),
      const SizedBox(height:12),
      GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.55,crossAxisSpacing:10,mainAxisSpacing:10,children:[
        reportStat(tr('Rent Received'),reportAmount(rent),Icons.payments_outlined),
        reportStat(tr('Maintenance Expenses'),reportAmount(maintenance),Icons.handyman_outlined),
        reportStat(tr('Net Cash Flow'),reportAmount(rent-maintenance),Icons.account_balance_wallet_outlined),
        reportStat(tr('Occupancy'),'$occupied / ${reportRows.length} • $vacant ${tr('Vacant')}',Icons.apartment_outlined),
      ]),
      const SizedBox(height:18),
      Text(tr('Property-wise Breakdown'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
      if(reportRows.isEmpty) Padding(padding:const EdgeInsets.only(top:16),child:Text(tr('No properties added yet.')))
      else ...reportRows.map((row){
        final received=(row['rent_received'] as num?)?.toDouble()??0;
        final expense=(row['maintenance_expense'] as num?)?.toDouble()??0;
        final active=(row['active_contract_count'] as num? ?? 0)>0;
        return Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(row['name'].toString(),style:const TextStyle(fontWeight:FontWeight.bold)),
          const SizedBox(height:6),
          Text('${tr('Occupancy')}: ${active?tr('Occupied'):tr('Vacant')}'),
          Text('${tr('Rent Received')}: ${reportAmount(received)}'),
          Text('${tr('Maintenance Expenses')}: ${reportAmount(expense)}'),
          Text('${tr('Net Cash Flow')}: ${reportAmount(received-expense)}',style:const TextStyle(fontWeight:FontWeight.w600)),
        ])));
      }),
    ]));
  }
  Widget reportStat(String label,String value,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
    Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:7),
    Text(value,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold),maxLines:1,overflow:TextOverflow.ellipsis),
    Text(label,style:Theme.of(context).textTheme.bodySmall,maxLines:1,overflow:TextOverflow.ellipsis),
  ])));
  Widget overview()=>RefreshIndicator(onRefresh:load,child:ListView(padding:const EdgeInsets.all(16),children:[
    GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),crossAxisCount:2,childAspectRatio:1.7,crossAxisSpacing:10,mainAxisSpacing:10,children:[
      stat('Properties',properties.length,Icons.home_work_outlined),stat('Tenants',tenants.length,Icons.people_outline),
      stat('Active Contracts',contracts.where((c)=>c['status']=='Active').length,Icons.description_outlined),
      stat('Vacant Properties',properties.where((p)=>p['status']=='Vacant').length,Icons.meeting_room_outlined),
      stat('Overdue Rent',rentPayments.where((p)=>p['status']=='Overdue').length,Icons.warning_amber),
      stat('Pending Rent',rentPayments.where((p)=>p['status']=='Pending'||p['status']=='Partial').length,Icons.schedule),
      stat('Open Maintenance',maintenanceItems.where((m)=>m['status']=='Open'||m['status']=='In Progress'||m['status']=='On Hold').length,Icons.handyman_outlined),
    ]),const SizedBox(height:18),Text(tr('Recent Properties'),style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold)),
    if(properties.isEmpty)Text(tr('No properties added yet.')) else ...properties.take(5).map(propertyTile),
  ]));
  Widget stat(String title,int n,IconData icon)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:Theme.of(context).colorScheme.primary),const SizedBox(height:7),Text('$n',style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold)),Text(tr(title),maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall)])));
  Widget nav(int i,IconData icon,String label){final selected=tab==i;return Expanded(child:InkWell(onTap:()=>setState(()=>tab=i),child:SizedBox(height:66,child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,size:22,color:selected?Theme.of(context).colorScheme.primary:Theme.of(context).hintColor),const SizedBox(height:2),Text(tr(label),style:TextStyle(fontSize:10,fontWeight:FontWeight.w600,color:selected?Theme.of(context).colorScheme.primary:Theme.of(context).hintColor))]))));}
  @override Widget build(BuildContext context){
    final pages=[overview(),listing(properties,'Properties'),listing(tenants,'Tenants'),listing(contracts,'Contracts'),listing(owners,'Owners'),listing(maintenanceItems,'Maintenance'),reports()];
    return Scaffold(appBar:AppBar(title:Text(tr('Properties Manager')),actions:[IconButton(tooltip:tr('Financial Reports'),onPressed:()=>setState(()=>tab=6),icon:const Icon(Icons.assessment_outlined)),IconButton(onPressed:load,icon:const Icon(Icons.refresh))]),
      body:loading?const Center(child:CircularProgressIndicator()):IndexedStack(index:tab,children:pages),
      bottomNavigationBar:Container(color:Theme.of(context).colorScheme.surface,child:SafeArea(top:false,child:SizedBox(height:66,child:Row(children:[
        nav(0,Icons.dashboard_outlined,'Overview'),nav(1,Icons.home_work_outlined,'Properties'),
        Expanded(child:InkWell(onTap:plusMenu,child:Center(child:Container(width:43,height:43,decoration:BoxDecoration(color:Theme.of(context).colorScheme.primary,borderRadius:BorderRadius.circular(15)),child:Icon(Icons.add_rounded,color:Theme.of(context).colorScheme.onPrimary,size:29))))),
        nav(2,Icons.people_outline,'Tenants'),nav(3,Icons.description_outlined,'Contracts'),nav(4,Icons.badge_outlined,'Owners'),nav(5,Icons.handyman_outlined,'Maintenance'),
      ])))),
    );
  }
}
