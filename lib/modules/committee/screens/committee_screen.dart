import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'package:flutter/material.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/modules/committee/services/committee_service.dart';
import 'package:my_finance/modules/finance/services/wallet_service.dart';

class CommitteeScreen extends StatefulWidget {
  const CommitteeScreen({super.key});
  @override
  State<CommitteeScreen> createState() => _CommitteeScreenState();
}

class _CommitteeScreenState extends State<CommitteeScreen> {
  List<Map<String, dynamic>> committees = [];
  bool loading = true;
  final money = NumberFormat('#,##0.##');
  @override
  void initState() { super.initState(); AppRefreshController.revision.addListener(_onAppDataChanged); _load(); }
  void _onAppDataChanged() { if (mounted) _load(); }
  @override
  void dispose() { AppRefreshController.revision.removeListener(_onAppDataChanged); super.dispose(); }

  Future<void> _load() async {
    try {
      final rows = await CommitteeService.getCommittees();
      if (mounted) setState(() { committees = rows; loading = false; });
    } catch (e) {
      if (mounted) setState(() => loading = false);
      _message(e.toString());
    }
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final amount = TextEditingController();
    final members = TextEditingController();
    String frequency = 'Monthly';
    DateTime start = DateTime.now();
    DateTime due = DateTime.now();

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
          final screenHeight = MediaQuery.sizeOf(context).height;
          final maxHeight = keyboardHeight > 0
              ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * .95
              : screenHeight * .82;

          return AnimatedPadding(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Create Committee',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: SingleChildScrollView(
                          primary: false,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: name,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(labelText: 'Committee name'),
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: amount,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Installment amount'),
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                value: frequency,
                                decoration: const InputDecoration(labelText: 'Frequency'),
                                items: ['Daily', 'Weekly', 'Monthly']
                                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v != null) setSheetState(() => frequency = v);
                                },
                              ),
                              const SizedBox(height: 10),
                              TextField(
                                controller: members,
                                minLines: 3,
                                maxLines: 6,
                                textCapitalization: TextCapitalization.words,
                                decoration: const InputDecoration(
                                  labelText: 'Members (one name per line)',
                                  hintText: 'Ali\\nAhmed\\nUsman',
                                  alignLabelWithHint: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Start date'),
                                subtitle: Text(DateFormat('dd MMM yyyy').format(start)),
                                trailing: const Icon(Icons.calendar_month),
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: sheetContext,
                                    initialDate: start,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) setSheetState(() => start = d);
                                },
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('First installment due'),
                                subtitle: Text(DateFormat('dd MMM yyyy').format(due)),
                                trailing: const Icon(Icons.event),
                                onTap: () async {
                                  final d = await showDatePicker(
                                    context: sheetContext,
                                    initialDate: due,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (d != null) setSheetState(() => due = d);
                                },
                              ),
                              Text(
                                'Turn order follows the member order entered above.',
                                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () => Navigator.pop(sheetContext, false),
                                      child: const Text('Cancel'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: FilledButton(
                                      onPressed: () => Navigator.pop(sheetContext, true),
                                      child: const Text('Create'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (ok == true) {
      try {
        final memberList = members.text
            .split(RegExp(r'[\\n,;]+'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .map((e) => {'name': e, 'phone': ''})
            .toList();
        await CommitteeService.createCommittee(
          name: name.text,
          frequency: frequency,
          installmentAmount: double.parse(amount.text),
          members: memberList,
          startDate: start,
          firstDueDate: due,
        );
        await SoundSettingsService.instance.play('save');
        await _load();
      } catch (e) {
        _message(e.toString());
      }
    }

    name.dispose();
    amount.dispose();
    members.dispose();
  }

  Future<void> _open(Map<String,dynamic> committee) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CommitteeDetailScreen(committee:committee)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Committee Management'), actions: [
        IconButton(tooltip: 'Add committee', onPressed: _create, icon: const Icon(Icons.group_add_rounded)),
      ]),
      body: loading ? const Center(child:CircularProgressIndicator()) :
        committees.isEmpty ? Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.groups_outlined,size:56,color:Theme.of(context).hintColor), const SizedBox(height:12),
          const Text('No committees yet',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:6), const Text('Create a fixed-turn committee and add its members.',textAlign:TextAlign.center),
          const SizedBox(height:16), FilledButton.icon(onPressed:_create,icon:const Icon(Icons.add),label:const Text('Create Committee')),
        ]))) :
        RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
          ...committees.map((c) {
            final collected=(c['collected'] as num?)?.toDouble()??0;
            final paid=(c['paid_out'] as num?)?.toDouble()??0;
            return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(
              contentPadding:const EdgeInsets.all(14), leading:const CircleAvatar(child:Icon(Icons.groups_2_outlined)),
              title:Text(c['name'].toString(),style:TextStyle(fontWeight:FontWeight.w800)),
              subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('${c['frequency']} • ${c['actual_members']} members • ${c['status']}'),
                const SizedBox(height:5), Text('Installment: ${c['currency'] ?? 'PKR'} ${money.format(c['installment_amount'])}'),
                Text('Collected: ${money.format(collected)}   •   Paid out: ${money.format(paid)}'),
                Text('Committee balance: ${money.format(c['available_balance'] ?? (collected-paid))} ${c['currency'] ?? 'PKR'}'),
              ])),
              trailing:const Icon(Icons.chevron_right), onTap:()=>_open(c),
            ));
          }),
        ])),
    );
  }
}

class CommitteeDetailScreen extends StatefulWidget {
  final Map<String,dynamic> committee;
  const CommitteeDetailScreen({super.key,required this.committee});
  @override
  State<CommitteeDetailScreen> createState()=>_CommitteeDetailScreenState();
}

class _CommitteeDetailScreenState extends State<CommitteeDetailScreen> with SingleTickerProviderStateMixin {
  late TabController tabs;
  List<Map<String,dynamic>> members=[];
  List<Map<String,dynamic>> entries=[];
  List<Map<String,dynamic>> wallets=[];
  bool loading=true;
  final money=NumberFormat('#,##0.##');
  late Map<String,dynamic> committeeData;
  int get id=>(committeeData['id'] as num).toInt();

  @override
  void initState(){super.initState();committeeData=Map<String,dynamic>.from(widget.committee);tabs=TabController(length:4,vsync:this);AppRefreshController.revision.addListener(_onAppDataChanged);_load();}
  void _onAppDataChanged(){if(mounted)_load();}
  @override
  void dispose(){AppRefreshController.revision.removeListener(_onAppDataChanged);tabs.dispose();super.dispose();}

  Future<void> _load() async {
    try{
      final values=await Future.wait([
        CommitteeService.getMembers(id),CommitteeService.getEntries(id),
        WalletService.getWallets(),
      ]);
      final currentCommittees=await CommitteeService.getCommittees();
      final current=currentCommittees.where((item)=>(item['id'] as num).toInt()==id);
      if(current.isNotEmpty) committeeData=Map<String,dynamic>.from(current.first);
      if(mounted)setState((){
        members=values[0] as List<Map<String,dynamic>>;
        entries=values[1] as List<Map<String,dynamic>>;
        wallets=values[2] as List<Map<String,dynamic>>;
        loading=false;
      });
    }catch(e){if(mounted)setState(()=>loading=false);_msg(e.toString());}
  }

  void _msg(String s){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));}

  Future<void> _addMember() async {
    final n=TextEditingController(),p=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add member'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:n,decoration:const InputDecoration(labelText:'Member name')),
        TextField(controller:p,decoration:const InputDecoration(labelText:'Phone (optional)'),keyboardType:TextInputType.phone),
      ]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Add'))]));
    if(ok==true){try{await CommitteeService.addMember(id,n.text,p.text);await SoundSettingsService.instance.play('save');await _load();}catch(e){_msg(e.toString());}}
  }

  Future<void> _moveMember(int index, int direction) async {
    final target=index+direction;
    if(target<0||target>=members.length||entries.isNotEmpty)return;
    final reordered=List<Map<String,dynamic>>.from(members);
    final current=reordered[index];
    reordered[index]=reordered[target];
    reordered[target]=current;
    try{
      await CommitteeService.reorderMembers(id,reordered.map((m)=>(m['id'] as num).toInt()).toList());
      await _load();
    }catch(e){_msg(e.toString());}
  }

  Future<void> _record(String type) async {
    if(members.isEmpty){_msg('Add members first.');return;}
    final pot=(committeeData['installment_amount'] as num).toDouble()*members.length;
    final eligibleMembers=type=='Payout'
      ? members.where((m)=>(m['received'] as num).toDouble()<pot-0.000001).take(1).toList()
      : members;
    if(eligibleMembers.isEmpty){_msg('All scheduled payouts are complete.');return;}
    final amount=TextEditingController(text: type=='Installment' ? '${committeeData['installment_amount']}' : '${pot-(eligibleMembers.first['received'] as num).toDouble()}');
    int memberId=(eligibleMembers.first['id'] as num).toInt();
    int? walletId=wallets.isEmpty?null:(wallets.first['id'] as num).toInt();
    String paymentMethod='Without Wallet';
    DateTime date=DateTime.now();final note=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(type=='Installment'?'Record Installment Payment':'Record Member Payout'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:memberId,decoration:const InputDecoration(labelText:'Member'),
          items:eligibleMembers.map((m)=>DropdownMenuItem(value:(m['id'] as num).toInt(),child:Text(m['name'].toString()))).toList(),
          onChanged:(v){if(v!=null)setD(()=>memberId=v);}),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Amount (${committeeData['currency'] ?? 'PKR'})')),
        DropdownButtonFormField<String>(value:paymentMethod,decoration:const InputDecoration(labelText:'Payment method'),
          items:const [
            DropdownMenuItem(value:'Without Wallet',child:Text('Record Without Wallet')),
            DropdownMenuItem(value:'Existing Wallet',child:Text('Use Existing Wallet')),
          ],
          onChanged:(v){if(v!=null)setD(()=>paymentMethod=v);}),
        if(paymentMethod=='Existing Wallet') ...[
          if(wallets.isEmpty) const Padding(padding:EdgeInsets.all(8),child:Text('No existing wallets available.')),
          if(wallets.isNotEmpty) DropdownButtonFormField<int>(value:walletId,decoration:InputDecoration(labelText:type=='Installment'?'Pay from Wallet':'Receive into Wallet'),
            items:wallets.map((w)=>DropdownMenuItem(value:(w['id'] as num).toInt(),child:Text('${w['name']} • ${w['currency']} ${money.format(w['balance'])}'))).toList(),
            onChanged:(v){setD(()=>walletId=v);}),
        ],
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Date'),subtitle:Text(DateFormat('dd MMM yyyy').format(date)),
          trailing:const Icon(Icons.calendar_today),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setD(()=>date=d);}),
        TextField(controller:note,decoration:const InputDecoration(labelText:'Note (optional)')),
        Text(type=='Installment'
          ? 'The committee ledger will receive this installment. A selected personal wallet is reduced only when you choose one.'
          : 'The committee ledger will pay this member. A selected personal wallet is increased only when you choose one.',
          style:TextStyle(fontSize:11,color:Theme.of(context).hintColor)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    )));
    if(ok==true){try{
      if(paymentMethod=='Existing Wallet'&&walletId==null){_msg('Select a wallet or choose Without Wallet.');return;}
      await CommitteeService.recordEntry(committeeId:id,memberId:memberId,entryType:type,
        amount:double.parse(amount.text.trim()),walletId:paymentMethod=='Existing Wallet'?walletId:null,date:date,note:note.text);
      await SoundSettingsService.instance.play(type.toLowerCase() == 'payout' ? 'expense' : 'income');
      await _load();
    }catch(e){_msg(e.toString());}}
  }

  @override
  Widget build(BuildContext context){
    final c=committeeData;
    return Scaffold(appBar:AppBar(title:Text(c['name'].toString()),actions:[
      PopupMenuButton<String>(onSelected:(v) async {
        if(v=='delete'){
          final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
            title:const Text('Move committee to Recycle Bin?'),
            content:const Text('Committee members, entries and linked wallet transactions will be archived. Wallet balances will be reversed.'),
            actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
              FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Delete'))]));
          if(confirmed==true){try{await SoundSettingsService.instance.play('delete_warning');await CommitteeService.deleteCommittee(id);await SoundSettingsService.instance.play('delete_success');if(mounted)Navigator.pop(context);}catch(e){_msg('Could not delete committee: $e');}}
        }
      },itemBuilder:(_)=>[const PopupMenuItem(value:'delete',child:Text('Move to Recycle Bin'))]),
    ],bottom:TabBar(controller:tabs,isScrollable:true,tabs:const[
      Tab(text:'Overview'),Tab(text:'Members'),Tab(text:'Schedule'),Tab(text:'History'),
    ])),
    floatingActionButton:PopupMenuButton<String>(icon:const Icon(Icons.add_circle,size:52),tooltip:'Add committee entry',
      onSelected:(v){if(v=='member')_addMember();if(v=='installment')_record('Installment');if(v=='payout')_record('Payout');},
      itemBuilder:(_)=>[
        if(entries.isEmpty) const PopupMenuItem(value:'member',child:Text('Add member')),
        const PopupMenuItem(value:'installment',child:Text('Record installment')),
        const PopupMenuItem(value:'payout',child:Text('Record payout')),
      ]),
    body:loading?const Center(child:CircularProgressIndicator()):TabBarView(controller:tabs,children:[
      _overview(c),_members(),_schedule(c),_history(),
    ]));
  }

  Widget _overview(Map<String,dynamic> c){
    final collected=entries.where((e)=>e['entry_type']=='Installment').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble());
    final payout=entries.where((e)=>e['entry_type']=='Payout').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble());
    final balance=collected-payout;
    final dueCycles=_dueCycles(c);
    final dueTotal=(c['installment_amount'] as num).toDouble()*dueCycles*members.length;
    final pending=(dueTotal-collected).clamp(0.0,double.infinity).toDouble();
    final next=members.where((m)=>(m['received'] as num).toDouble()<(c['installment_amount'] as num).toDouble()*members.length-0.000001).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(c['status'].toString().toUpperCase(),style:TextStyle(fontWeight:FontWeight.bold,color:Theme.of(context).colorScheme.secondary)),
        const SizedBox(height:8),Text('${c['frequency']} • ${members.length} members'),
        Text('Installment: ${money.format(c['installment_amount'])} ${c['currency'] ?? 'PKR'}'),
        Text('Start: ${DateFormat('dd MMM yyyy').format(DateTime.parse(c['start_date']))}'),
      ]))),
      Row(children:[
        Expanded(child:_stat('Total collected',collected,Theme.of(context).colorScheme.secondary)),const SizedBox(width:8),
        Expanded(child:_stat('Total payouts',payout,Theme.of(context).colorScheme.tertiary)),
      ]),
      Row(children:[
        Expanded(child:_stat('Available balance',balance,Theme.of(context).colorScheme.primary)),const SizedBox(width:8),
        Expanded(child:_stat('Pending collection',pending,Theme.of(context).colorScheme.tertiary)),
      ]),
      Card(child:ListTile(title:const Text('Next payout turn'),subtitle:Text(next.isEmpty?'All members have received a payout':next.first['name'].toString()),leading:const Icon(Icons.event_available))),
      const SizedBox(height:8),
      Wrap(spacing:8,children:[
        OutlinedButton(onPressed:()=>_record('Installment'),child:const Text('Record installment')),
        OutlinedButton(onPressed:()=>_record('Payout'),child:const Text('Record payout')),
        OutlinedButton(onPressed:()=>_changeStatus(),child:const Text('Change status')),
      ]),
      Padding(padding:EdgeInsets.only(top:12),child:Text('Committee funds are kept in this module and are separate from personal Wallet balances.',style:TextStyle(fontSize:12,color:Theme.of(context).hintColor))),
    ]);
  }

  Widget _stat(String title,double value,Color color)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:TextStyle(color:Theme.of(context).hintColor)),const SizedBox(height:5),
    Text(money.format(value),style:TextStyle(fontWeight:FontWeight.w800,fontSize:18,color:color)),
  ])));

  Widget _members(){
    final c=committeeData;
    final pot=(c['installment_amount'] as num).toDouble()*members.length;
    final dueCount=_dueCycles(c);
    final dueAmount=(c['installment_amount'] as num).toDouble()*dueCount;
    return ListView(padding:const EdgeInsets.all(12),children:[
      if(entries.isEmpty) Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:_addMember,icon:const Icon(Icons.person_add),label:const Text('Add member'))),
      ...members.map((m){
        final paid=(m['paid'] as num).toDouble();
        final remaining=(dueAmount-paid).clamp(0.0,pot);
        final paymentStatus=dueCount==0?'Upcoming':remaining<=0.000001?'Paid':paid>0?'Partial':'Overdue';
        return Card(child:ListTile(leading:CircleAvatar(child:Text(m['turn_no'].toString())),
          title:Text(m['name'].toString()),
          subtitle:Text('$paymentStatus • Paid: ${money.format(paid)} • Due: ${money.format(dueAmount)} • Remaining: ${money.format(remaining)}\nPayout received: ${money.format(m['received'])}'),
          isThreeLine:true,
          onTap:()=>_showMemberLedger(m),
          trailing:entries.isEmpty?Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(visualDensity:VisualDensity.compact,onPressed:()=>_moveMember(members.indexOf(m),-1),icon:const Icon(Icons.arrow_upward,size:18)),
            IconButton(visualDensity:VisualDensity.compact,onPressed:()=>_moveMember(members.indexOf(m),1),icon:const Icon(Icons.arrow_downward,size:18)),
          ]):Text(m['phone']?.toString()??'',style:TextStyle(fontSize:11))));
      }),
    ]);
  }

  Future<void> _showMemberLedger(Map<String,dynamic> member) async {
    final memberId=(member['id'] as num).toInt();
    final rows=entries.where((e)=>(e['member_id'] as num).toInt()==memberId).toList();
    final paid=rows.where((e)=>e['entry_type']=='Installment').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble());
    final received=rows.where((e)=>e['entry_type']=='Payout').fold<double>(0,(s,e)=>s+(e['amount'] as num).toDouble());
    await showModalBottomSheet<void>(context:context,isScrollControlled:true,showDragHandle:true,
      builder:(ctx)=>SafeArea(child:Padding(padding:const EdgeInsets.fromLTRB(16,0,16,20),child:SizedBox(
        height:MediaQuery.of(ctx).size.height*0.72,
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(member['name'].toString(),style:Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height:8),
          Text('Installments: ${money.format(paid)} • Payout received: ${money.format(received)}',
            style:TextStyle(fontWeight:FontWeight.w600)),
          const Divider(height:20),
          Expanded(child:rows.isEmpty?const Center(child:Text('No entries for this member yet.')):
            ListView.builder(itemCount:rows.length,itemBuilder:(context,index){
              final e=rows[index];final deposit=e['entry_type']=='Installment';
              final date=DateTime.tryParse(e['entry_date']?.toString()??'');
              final method=e['payment_method']=='Wallet'
                ? 'Wallet: ${e['wallet_name']??'Unavailable'}'
                : 'Without Wallet';
              return ListTile(
                contentPadding:EdgeInsets.zero,
                leading:Icon(deposit?Icons.call_received:Icons.call_made,color:deposit?Theme.of(context).colorScheme.secondary:Theme.of(context).colorScheme.tertiary),
                title:Text('${e['entry_type']} • ${committeeData['currency']??'PKR'} ${money.format(e['amount'])}'),
                subtitle:Text('${date==null?'':DateFormat('dd MMM yyyy').format(date)} • $method${(e['note']??'').toString().isEmpty?'':' • ${e['note']}'}'),
                trailing:Icon(deposit?Icons.add:Icons.remove,color:deposit?Theme.of(context).colorScheme.secondary:Theme.of(context).colorScheme.tertiary),
              );
            })),
        ]),
      ))));
  }

  int _dueCycles(Map<String,dynamic> c){
    final first=DateTime.parse(c['first_due_date']);
    final today=DateTime.now();
    final start=DateTime(first.year,first.month,first.day);
    final now=DateTime(today.year,today.month,today.day);
    if(now.isBefore(start))return 0;
    final frequency=c['frequency'].toString();
    int count;
    if(frequency=='Daily'){count=now.difference(start).inDays+1;}
    else if(frequency=='Weekly'){count=now.difference(start).inDays~/7+1;}
    else{
      count=(now.year-start.year)*12+now.month-start.month+1;
      if(now.day<start.day)count--;
    }
    return count.clamp(0,members.length).toInt();
  }

  Widget _schedule(Map<String,dynamic> c){
    final frequency=c['frequency'].toString();final base=DateTime.parse(c['first_due_date']);
    DateTime due(int n){if(frequency=='Daily')return base.add(Duration(days:n));if(frequency=='Weekly')return base.add(Duration(days:7*n));final year=base.year+(base.month-1+n)~/12;final month=(base.month-1+n)%12+1;final day=base.day.clamp(1,DateUtils.getDaysInMonth(year,month)).toInt();return DateTime(year,month,day);}
    return ListView(padding:const EdgeInsets.all(12),children:[
      const Padding(padding:EdgeInsets.all(8),child:Text('Fixed payout order • turn sequence follows member order')),
      ...members.map((m){final turn=(m['turn_no'] as num).toInt();return Card(child:ListTile(
        leading:CircleAvatar(child:Text('$turn')),title:Text(m['name'].toString()),
        subtitle:Text('${DateFormat('dd MMM yyyy').format(due(turn-1))} • ${(m['received'] as num).toDouble() >= (c['installment_amount'] as num).toDouble()*members.length-0.000001 ? 'Paid' : (m['received'] as num).toDouble()>0 ? 'Partial' : 'Pending'}'),
        trailing:Text('${money.format((c['installment_amount'] as num).toDouble()*members.length)} ${c['currency'] ?? 'PKR'}'),
      ));}),
    ]);
  }

  Widget _history()=>entries.isEmpty?const Center(child:Text('No committee entries yet.')):ListView.builder(
    padding:const EdgeInsets.all(12),itemCount:entries.length,itemBuilder:(context,i){
      final e=entries[i];final deposit=e['entry_type']=='Installment';
      return Card(child:ListTile(leading:CircleAvatar(child:Icon(deposit?Icons.south_west:Icons.north_east,color:deposit?Theme.of(context).colorScheme.secondary:Theme.of(context).colorScheme.tertiary)),
        title:Text('${e['member_name']} • ${e['entry_type']}'),
        subtitle:Text('${DateFormat('dd MMM yyyy').format(DateTime.parse(e['entry_date']))} • ${e['payment_method']=='Wallet' ? 'Wallet: ${e['wallet_name'] ?? 'Unavailable'} • ${money.format(e['wallet_amount'])} ${e['wallet_currency']}' : 'Without Wallet'}'),
        trailing:Text('${deposit?'+':'−'} ${e['committee_currency'] ?? committeeData['currency'] ?? 'PKR'} ${money.format(e['amount'])}',style:TextStyle(fontWeight:FontWeight.bold,color:deposit?Theme.of(context).colorScheme.secondary:Theme.of(context).colorScheme.tertiary)),
      ));
    });

  Future<void> _changeStatus()async{
    String status=committeeData['status'].toString();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Committee status'),
      content:DropdownButtonFormField<String>(value:status,items:['Upcoming','Active','Completed'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)setD(()=>status=v);}),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    )));
    if(ok==true){await CommitteeService.updateStatus(id,status);await SoundSettingsService.instance.play('update');committeeData['status']=status;if(mounted)setState(()=>{});_msg('Status updated.');}
  }
}
