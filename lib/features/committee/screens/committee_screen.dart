import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/features/committee/services/committee_service.dart';

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
  void initState() { super.initState(); _load(); }

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
    final ok = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, setD) => AlertDialog(
        title: const Text('Create Committee'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Committee name')),
          const SizedBox(height: 10),
          TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Installment amount')),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(value: frequency, decoration: const InputDecoration(labelText: 'Frequency'),
            items: ['Daily','Weekly','Monthly'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),
            onChanged: (v) { if(v!=null) setD(()=>frequency=v); }),
          const SizedBox(height: 10),
          TextField(controller: members, minLines: 3, maxLines: 6,
            decoration: const InputDecoration(labelText: 'Members (one name per line)', hintText: 'Ali\nAhmed\nUsman')),
          const SizedBox(height: 8),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('Start date'), subtitle: Text(DateFormat('dd MMM yyyy').format(start)),
            trailing: const Icon(Icons.calendar_month), onTap: () async { final d=await showDatePicker(context: context, initialDate:start, firstDate:DateTime(2000), lastDate:DateTime(2100)); if(d!=null)setD(()=>start=d); }),
          ListTile(contentPadding: EdgeInsets.zero, title: const Text('First installment due'), subtitle: Text(DateFormat('dd MMM yyyy').format(due)),
            trailing: const Icon(Icons.event), onTap: () async { final d=await showDatePicker(context: context, initialDate:due, firstDate:DateTime(2000), lastDate:DateTime(2100)); if(d!=null)setD(()=>due=d); }),
          const Text('Turn order follows the member order entered above.', style: TextStyle(fontSize: 12, color: Colors.black54)),
        ])),
        actions: [TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Create'))],
      )));
    if (ok != true) return;
    try {
      final memberList = members.text.split(RegExp(r'[\n,;]+')).map((e)=>e.trim()).where((e)=>e.isNotEmpty)
        .map((e)=>{'name':e,'phone':''}).toList();
      await CommitteeService.createCommittee(name:name.text, frequency:frequency,
        installmentAmount:double.parse(amount.text), members:memberList, startDate:start, firstDueDate:due);
      await _load();
    } catch(e) { _message(e.toString()); }
  }

  Future<void> _open(Map<String,dynamic> committee) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CommitteeDetailScreen(committee:committee)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Committee Management')),
      floatingActionButton: FloatingActionButton.extended(onPressed:_create, icon:const Icon(Icons.add), label:const Text('New Committee')),
      body: loading ? const Center(child:CircularProgressIndicator()) :
        committees.isEmpty ? Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[
          const Icon(Icons.groups_outlined,size:56,color:Colors.grey), const SizedBox(height:12),
          const Text('No committees yet',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:6), const Text('Create a fixed-turn committee and add its members.',textAlign:TextAlign.center),
          const SizedBox(height:16), FilledButton.icon(onPressed:_create,icon:const Icon(Icons.add),label:const Text('Create Committee')),
        ]))) :
        RefreshIndicator(onRefresh:_load,child:ListView(padding:const EdgeInsets.all(16),children:[
          Card(child:ListTile(
            leading:const CircleAvatar(child:Icon(Icons.account_balance_wallet_outlined)),
            title:const Text('Shared Committee Wallet',style:TextStyle(fontWeight:FontWeight.w700)),
            subtitle:const Text('One common wallet used by all committees. View its balance in Wallets.'),
          )),
          const SizedBox(height:8),
          ...committees.map((c) {
            final collected=(c['collected'] as num?)?.toDouble()??0;
            final paid=(c['paid_out'] as num?)?.toDouble()??0;
            return Card(margin:const EdgeInsets.only(bottom:10),child:ListTile(
              contentPadding:const EdgeInsets.all(14), leading:const CircleAvatar(child:Icon(Icons.groups_2_outlined)),
              title:Text(c['name'].toString(),style:const TextStyle(fontWeight:FontWeight.w800)),
              subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text('${c['frequency']} • ${c['actual_members']} members • ${c['status']}'),
                const SizedBox(height:5), Text('Installment: ${money.format(c['installment_amount'])}'),
                Text('Collected: ${money.format(collected)}   •   Paid out: ${money.format(paid)}'),
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
  int committeeWallet=-1;
  bool loading=true;
  final money=NumberFormat('#,##0.##');
  int get id=>(widget.committee['id'] as num).toInt();

  @override
  void initState(){super.initState();tabs=TabController(length:4,vsync:this);_load();}
  @override
  void dispose(){tabs.dispose();super.dispose();}

  Future<void> _load() async {
    try{
      final values=await Future.wait([
        CommitteeService.getMembers(id),CommitteeService.getEntries(id),
        CommitteeService.getWallets(),CommitteeService.sharedWalletId(),
      ]);
      if(mounted)setState((){
        members=values[0] as List<Map<String,dynamic>>;
        entries=values[1] as List<Map<String,dynamic>>;
        wallets=values[2] as List<Map<String,dynamic>>;
        committeeWallet=values[3] as int;loading=false;
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
    if(ok==true){try{await CommitteeService.addMember(id,n.text,p.text);await _load();}catch(e){_msg(e.toString());}}
  }

  Future<void> _record(String type) async {
    if(members.isEmpty||wallets.isEmpty){_msg('Add members and wallets first.');return;}
    final amount=TextEditingController(text: type=='Installment'?' ${widget.committee['installment_amount']}':'');
    final pot=(widget.committee['installment_amount'] as num).toDouble()*members.length;
    final eligibleMembers=type=='Payout'
      ? members.where((m)=>(m['received'] as num).toDouble()<pot-0.000001).take(1).toList()
      : members;
    if(eligibleMembers.isEmpty){_msg('All scheduled payouts are complete.');return;}
    int memberId=(eligibleMembers.first['id'] as num).toInt();
    int walletId=wallets.any((w)=>(w['id'] as num).toInt()==committeeWallet)?committeeWallet:(wallets.first['id'] as num).toInt();
    DateTime date=DateTime.now();final note=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:Text(type=='Installment'?'Record Installment Deposit':'Record Member Payout'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        DropdownButtonFormField<int>(value:memberId,decoration:const InputDecoration(labelText:'Member'),
          items:eligibleMembers.map((m)=>DropdownMenuItem(value:(m['id'] as num).toInt(),child:Text(m['name'].toString()))).toList(),
          onChanged:(v){if(v!=null)setD(()=>memberId=v);}),
        TextField(controller:amount,keyboardType:const TextInputType.numberWithOptions(decimal:true),decoration:InputDecoration(labelText:'Amount (${widget.committee['currency'] ?? 'PKR'})')),
        DropdownButtonFormField<int>(value:walletId,decoration:InputDecoration(labelText:type=='Installment'?'Deposit into':'Pay from'),
          items:wallets.map((w)=>DropdownMenuItem(value:(w['id'] as num).toInt(),child:Text('${w['name']} (${w['currency']})'))).toList(),
          onChanged:(v){if(v!=null)setD(()=>walletId=v);}),
        ListTile(contentPadding:EdgeInsets.zero,title:const Text('Date'),subtitle:Text(DateFormat('dd MMM yyyy').format(date)),
          trailing:const Icon(Icons.calendar_today),onTap:()async{final d=await showDatePicker(context:ctx,initialDate:date,firstDate:DateTime(2000),lastDate:DateTime(2100));if(d!=null)setD(()=>date=d);}),
        TextField(controller:note,decoration:const InputDecoration(labelText:'Note (optional)')),
        if(type=='Installment') const Text('Default destination is Committee Wallet. Each new entry resets to this wallet.',style:TextStyle(fontSize:11,color:Colors.black54)),
        if(type=='Payout') const Text('Committee Wallet is the default source. Insufficient balance is not allowed.',style:TextStyle(fontSize:11,color:Colors.black54)),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    )));
    if(ok==true){try{
      await CommitteeService.recordEntry(committeeId:id,memberId:memberId,entryType:type,
        amount:double.parse(amount.text.trim()),walletId:walletId,date:date,note:note.text);
      await _load();
    }catch(e){_msg(e.toString());}}
  }

  @override
  Widget build(BuildContext context){
    final c=widget.committee;
    return Scaffold(appBar:AppBar(title:Text(c['name'].toString()),bottom:TabBar(controller:tabs,isScrollable:true,tabs:const[
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
    final next=members.where((m)=>(m['received'] as num).toDouble()==0).toList();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(c['status'].toString().toUpperCase(),style:const TextStyle(fontWeight:FontWeight.bold,color:Colors.green)),
        const SizedBox(height:8),Text('${c['frequency']} • ${members.length} members'),
        Text('Installment: ${money.format(c['installment_amount'])}'),
        Text('Start: ${DateFormat('dd MMM yyyy').format(DateTime.parse(c['start_date']))}'),
      ]))),
      Row(children:[
        Expanded(child:_stat('Collected',collected,Colors.green)),const SizedBox(width:8),
        Expanded(child:_stat('Payouts',payout,Colors.deepPurple)),
      ]),
      Card(child:ListTile(title:const Text('Next payout turn'),subtitle:Text(next.isEmpty?'All members have received a payout':next.first['name'].toString()),leading:const Icon(Icons.event_available))),
      Card(child:ListTile(title:const Text('Committee wallet'),subtitle:const Text('Shared by all committees'),trailing:const Icon(Icons.account_balance_wallet))),
      const SizedBox(height:8),
      Wrap(spacing:8,children:[
        OutlinedButton(onPressed:()=>_record('Installment'),child:const Text('Record deposit')),
        OutlinedButton(onPressed:()=>_record('Payout'),child:const Text('Record payout')),
        OutlinedButton(onPressed:()=>_changeStatus(),child:const Text('Change status')),
      ]),
    ]);
  }

  Widget _stat(String title,double value,Color color)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    Text(title,style:const TextStyle(color:Colors.black54)),const SizedBox(height:5),
    Text(money.format(value),style:TextStyle(fontWeight:FontWeight.w800,fontSize:18,color:color)),
  ])));

  Widget _members(){
    final c=widget.committee;
    final pot=(c['installment_amount'] as num).toDouble()*members.length;
    final dueCount=_dueCycles(c);
    final dueAmount=(c['installment_amount'] as num).toDouble()*dueCount;
    return ListView(padding:const EdgeInsets.all(12),children:[
      if(entries.isEmpty) Align(alignment:Alignment.centerRight,child:TextButton.icon(onPressed:_addMember,icon:const Icon(Icons.person_add),label:const Text('Add member'))),
      ...members.map((m){
        final paid=(m['paid'] as num).toDouble();
        final remaining=(dueAmount-paid).clamp(0.0,pot);
        return Card(child:ListTile(leading:CircleAvatar(child:Text(m['turn_no'].toString())),
          title:Text(m['name'].toString()),
          subtitle:Text('Paid: ${money.format(paid)} • Due: ${money.format(dueAmount)} • Remaining: ${money.format(remaining)}\nPayout received: ${money.format(m['received'])}'),
          isThreeLine:true,
          trailing:Text(m['phone']?.toString()??'',style:const TextStyle(fontSize:11))));
      }),
    ]);
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
        subtitle:Text(DateFormat('dd MMM yyyy').format(due(turn-1))),
        trailing:Text(money.format((c['installment_amount'] as num).toDouble()*members.length)),
      ));}),
    ]);
  }

  Widget _history()=>entries.isEmpty?const Center(child:Text('No committee entries yet.')):ListView.builder(
    padding:const EdgeInsets.all(12),itemCount:entries.length,itemBuilder:(context,i){
      final e=entries[i];final deposit=e['entry_type']=='Installment';
      return Card(child:ListTile(leading:CircleAvatar(child:Icon(deposit?Icons.south_west:Icons.north_east,color:deposit?Colors.green:Colors.deepPurple)),
        title:Text('${e['member_name']} • ${e['entry_type']}'),
        subtitle:Text('${DateFormat('dd MMM yyyy').format(DateTime.parse(e['entry_date']))} • ${money.format(e['wallet_amount'] ?? e['amount'])} ${e['wallet_currency']} → ${e['wallet_name']}'),
        trailing:Text('${deposit?'+':'−'} ${e['committee_currency'] ?? widget.committee['currency'] ?? 'PKR'} ${money.format(e['amount'])}',style:TextStyle(fontWeight:FontWeight.bold,color:deposit?Colors.green:Colors.deepPurple)),
      ));
    });

  Future<void> _changeStatus()async{
    String status=widget.committee['status'].toString();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>StatefulBuilder(builder:(ctx,setD)=>AlertDialog(
      title:const Text('Committee status'),
      content:DropdownButtonFormField<String>(value:status,items:['Upcoming','Active','Completed'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v){if(v!=null)setD(()=>status=v);}),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Save'))],
    )));
    if(ok==true){await CommitteeService.updateStatus(id,status);if(mounted)setState(()=>{});_msg('Status updated.');}
  }
}
