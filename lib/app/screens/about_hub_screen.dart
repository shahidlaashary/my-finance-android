import 'dart:io';
import 'package:flutter/material.dart';
import 'package:my_finance/core/localization/app_text.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AboutHubScreen extends StatelessWidget {
  const AboutHubScreen({super.key});
  @override Widget build(BuildContext context){
    final sections=[
      _AboutEntry('App Details','Version, developer and application information',Icons.info_outline,()=>_open(context,const _AppDetailsPage())),
      _AboutEntry("What's New",'Latest changes and release notes',Icons.new_releases_outlined,()=>_open(context,const _WhatsNewPage())),
      _AboutEntry('Quick Tour','A short guide to the main app features',Icons.explore_outlined,()=>_open(context,const _QuickTourPage())),
      _AboutEntry('Privacy Policy','How your information is stored and handled',Icons.privacy_tip_outlined,()=>_open(context,const _PrivacyPage())),
      _AboutEntry('Terms of Use','Important terms for using My Finance',Icons.gavel_outlined,()=>_open(context,const _TermsPage())),
      _AboutEntry('Open Source Licenses','Licenses for third-party packages',Icons.article_outlined,()=>showLicensePage(context:context,applicationName:'My Finance',applicationVersion:'1.0.0',applicationLegalese:'© ${DateTime.now().year} Shahid Laashary')),
      _AboutEntry('Storage Information','Local database and attachment storage details',Icons.storage_outlined,()=>_open(context,const _StoragePage())),
    ];
    return Scaffold(appBar:AppBar(title:Text(appText(context, "About My Finance", "About My Finance"),style:TextStyle(fontWeight:FontWeight.w800))),body:ListView(padding:const EdgeInsets.all(16),children:[
      Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_balance_wallet_rounded,
                color: Theme.of(context).colorScheme.primary, size: 29),
            ),
            const SizedBox(height: 12),
            Text(appText(context, "MY FINANCE", "MY FINANCE"),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface,
                fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
            const SizedBox(height: 5),
            Text(appText(context, "Your Money. Your Control.", "Your Money. Your Control."),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(appText(context, "Smart • Simple • Secure", "Smart • Simple • Secure"),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11)),
            const SizedBox(height: 6),
            Text('© ${DateTime.now().year} My Finance. All rights reserved.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10)),
            const SizedBox(height: 4),
            Text(appText(context, "Made with care for better financial management.", "Made with care for better financial management."),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10)),
          ],
        ),
      ),
      ...sections.map((s)=>Card(margin:const EdgeInsets.only(bottom:9),child:ListTile(leading:Icon(s.icon,color:Theme.of(context).colorScheme.primary),title:Text(s.title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Text(s.subtitle),trailing:const Icon(Icons.chevron_right_rounded),onTap:s.action))),
    ]));
  }
  static void _open(BuildContext context,Widget page)=>Navigator.push(context,MaterialPageRoute(builder:(_)=>page));
}
class _AboutEntry{final String title,subtitle;final IconData icon;final VoidCallback action;const _AboutEntry(this.title,this.subtitle,this.icon,this.action);}
class _InfoPage extends StatelessWidget{
  final String title;final IconData icon;final List<Widget> children;
  const _InfoPage({required this.title,required this.icon,required this.children});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(title)),body:ListView(padding:const EdgeInsets.all(18),children:[Icon(icon,size:38,color:Theme.of(context).colorScheme.primary),const SizedBox(height:14),...children]));
}
class _AppDetailsPage extends StatelessWidget{
  const _AppDetailsPage();
  @override Widget build(BuildContext context)=>const _InfoPage(title:'App Details',icon:Icons.account_balance_wallet_rounded,children:[
    _SectionTitle('My Finance'),_BodyText('My Finance is a personal finance management app designed to help organize accounts, income, expenses, budgets, savings goals, loans, assets, recurring transactions, documents and other financial records.'),
    _SectionTitle('Application Information'),_InfoLine('App name','My Finance'),_InfoLine('Version','1.0.0'),_InfoLine('Developer','Shahid Laashary'),_InfoLine('Platform','Flutter • Android'),_InfoLine('Data storage','Local SQLite database'),
    _SectionTitle('Our Approach'),_BodyText('The app is designed to keep your finance records organized on your device. You remain responsible for reviewing your entries and keeping backup copies of important information.'),
  ]);
}
class _WhatsNewPage extends StatelessWidget{
  const _WhatsNewPage();
  @override Widget build(BuildContext context)=>const _InfoPage(title:"What's New",icon:Icons.new_releases_outlined,children:[
    _SectionTitle('Current app version • 1.0.0'),_BodyText('This section is reserved for version-by-version release notes. Updates will be listed here as they are included in published app releases.'),
    _SectionTitle('Main app areas'),_BulletList(['Accounts and multi-currency wallets','Income, expense and transfer tracking','Budgets, savings goals and reports','Loans, repayments and debt planning','Assets, vehicles and recurring transactions','Documents and local attachments']),
    _BodyText('Note: Features shown in development builds may change before a public release.'),
  ]);
}
class _QuickTourPage extends StatefulWidget{const _QuickTourPage();@override State<_QuickTourPage> createState()=>_QuickTourPageState();}
class _QuickTourPageState extends State<_QuickTourPage>{
  final _controller=PageController();int _index=0;
  final _steps=const [
    (Icons.dashboard_outlined,'Dashboard','Get an overview of your finances, balances and recent activity.'),
    (Icons.account_balance_wallet_outlined,'Accounts & Wallets','Create accounts in different currencies and track their balances.'),
    (Icons.swap_horiz_rounded,'Transactions','Record income, expenses and transfers, and review your transaction history.'),
    (Icons.pie_chart_outline,'Budgets & Goals','Set spending limits and track progress towards savings targets.'),
    (Icons.handshake,'Loans & Debt','Track money lent to others separately from debts you need to repay.'),
    (Icons.inventory_2_outlined,'More Features','Explore stock management, documents, vehicles, exchange rates and other tools.'),
    (Icons.shield_outlined,'Keep your data safe','Review storage information and create backups regularly using the available backup tools.'),
  ];
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(appText(context, "Quick Tour", "Quick Tour"))),body:Column(children:[
    Expanded(child:PageView.builder(controller:_controller,itemCount:_steps.length,onPageChanged:(v)=>setState(()=>_index=v),itemBuilder:(context,i){final s=_steps[i];return Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(s.$1,size:76,color:Theme.of(context).colorScheme.primary),const SizedBox(height:28),Text(s.$2,style:Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight:FontWeight.w800)),const SizedBox(height:14),Text(s.$3,textAlign:TextAlign.center,style:Theme.of(context).textTheme.bodyLarge)]));})),
    Padding(padding:const EdgeInsets.fromLTRB(20,8,20,28),child:Row(children:[Text('${_index+1} / ${_steps.length}'),const Spacer(),TextButton(onPressed:_index==0?null:()=>_controller.previousPage(duration:const Duration(milliseconds:220),curve:Curves.easeOut),child:Text(appText(context, "Back", "Back"))),const SizedBox(width:8),FilledButton(onPressed:()=>_index==_steps.length-1?Navigator.pop(context):_controller.nextPage(duration:const Duration(milliseconds:220),curve:Curves.easeOut),child:Text(_index==_steps.length-1?'Finish':'Next'))])),
  ]));
}
class _PrivacyPage extends StatelessWidget{
  const _PrivacyPage();
  @override Widget build(BuildContext context)=>const _InfoPage(title:'Privacy Policy',icon:Icons.privacy_tip_outlined,children:[
    _SectionTitle('1. Information you enter'),_BodyText('My Finance may store financial information you choose to enter, such as account names, balances, transactions, budgets, loans, goals, stock records and notes. Attachments you add are also stored as files on your device.'),
    _SectionTitle('2. Local storage'),_BodyText('The current app uses a local SQLite database for financial records and local application storage for attachments. The project documentation describes cloud synchronization and remote backup as planned features, not currently available services.'),
    _SectionTitle('3. Network services'),_BodyText('Some optional features, such as online exchange-rate retrieval, may connect to external services when you use them. Those services have their own privacy practices.'),
    _SectionTitle('4. Sharing and disclosure'),_BodyText('The app does not provide an in-app account or cloud-sync service in its current documented configuration. If you export or share a backup, report or attachment, that action is controlled by you and the destination service may process the shared file.'),
    _SectionTitle('5. Security and backups'),_BodyText('Device security settings help protect locally stored information. Keep your device updated and create secure backups of important records. Anyone with access to an unlocked device or an exported backup may be able to view its contents.'),
    _SectionTitle('6. Your choices'),_BodyText('You control the information you enter and can use the app’s available record-management and backup tools. Removing the app or its data may remove locally stored information.'),
    _SectionTitle('7. Policy updates'),_BodyText('This policy may be updated when app features or data practices change. Check this section after installing a new version.'),
    _BodyText('Last updated: November 2026.'),
  ]);
}
class _TermsPage extends StatelessWidget{
  const _TermsPage();
  @override Widget build(BuildContext context)=>const _InfoPage(title:'Terms of Use',icon:Icons.gavel_outlined,children:[
    _SectionTitle('1. Acceptable use'),_BodyText('You may use My Finance to organize personal or business financial records. You are responsible for ensuring that your use complies with applicable laws.'),
    _SectionTitle('2. Accuracy of records'),_BodyText('You are responsible for the accuracy and completeness of information entered into the app. Calculations, forecasts, reminders and summaries are provided as organizational tools and may not reflect bank or lender statements.'),
    _SectionTitle('3. No financial or tax advice'),_BodyText('My Finance is not a bank, lender, investment adviser, accountant or tax professional. Information and estimates in the app are not financial, legal, tax or investment advice. Consult a qualified professional for decisions requiring such advice.'),
    _SectionTitle('4. Data and backups'),_BodyText('You are responsible for protecting your device and maintaining backups of important records. The developer is not responsible for loss caused by device failure, accidental deletion, unauthorized access or an incorrectly restored backup, to the extent permitted by law.'),
    _SectionTitle('5. Third-party services'),_BodyText('Optional integrations or external services may be governed by their own terms. Their availability and accuracy are not controlled by the app.'),
    _SectionTitle('6. Changes and availability'),_BodyText('Features may be changed, improved or removed as the app develops. The app is provided on an as-available basis, subject to applicable law.'),
    _SectionTitle('7. Contact'),_BodyText('For app-related questions, use the developer contact channel through which you obtained My Finance.'),
    _BodyText('Last updated: November 2026.'),
  ]);
}
class _StoragePage extends StatefulWidget{const _StoragePage();@override State<_StoragePage> createState()=>_StoragePageState();}
class _StoragePageState extends State<_StoragePage>{
  bool _loading=true;String? _dbPath,_attachmentPath;int _dbBytes=0,_attachmentBytes=0,_attachmentFiles=0;String? _error;
  @override void initState(){super.initState();_load();}
  Future<int> _folderSize(Directory dir)async{if(!await dir.exists())return 0;var total=0;await for(final e in dir.list(recursive:true,followLinks:false)){if(e is File){try{total+=await e.length();_attachmentFiles++;}catch(_){}}}return total;}
  String _size(int n){if(n<1024)return '$n B';if(n<1024*1024)return '${(n/1024).toStringAsFixed(1)} KB';if(n<1024*1024*1024)return '${(n/1024/1024).toStringAsFixed(2)} MB';return '${(n/1024/1024/1024).toStringAsFixed(2)} GB';}
  Future<void> _refresh()async{setState((){_loading=true;_dbBytes=0;_attachmentBytes=0;_attachmentFiles=0;_error=null;});await _load();}
  Future<void> _load()async{try{final dbDir=await getDatabasesPath();final dbPath=p.join(dbDir,'my_finance.db');final dbFile=File(dbPath);final docs=await getApplicationDocumentsDirectory();final attach=Directory(p.join(docs.path,'my_finance_attachments'));final bytes=await _folderSize(attach);if(mounted)setState(()=>_dbPath=dbPath);if(mounted)setState(()=>_attachmentPath=attach.path);if(await dbFile.exists())_dbBytes=await dbFile.length();_attachmentBytes=bytes;}catch(e){_error=e.toString();}finally{if(mounted)setState(()=>_loading=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(appText(context, "Storage Information", "Storage Information")),actions:[IconButton(onPressed:_refresh,icon:const Icon(Icons.refresh))]),body:_loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(18),children:[
    if(_error!=null)Text('Could not read storage information: $_error'),
    _SectionTitle('Storage Summary'),_InfoLine('Database size',_size(_dbBytes)),_InfoLine('Attachments size',_size(_attachmentBytes)),_InfoLine('Attachment files','$_attachmentFiles'),_InfoLine('Total measured size',_size(_dbBytes+_attachmentBytes)),
    const SizedBox(height:16),_SectionTitle('Database Storage'),_BodyText('Financial records are stored in the app’s local SQLite database.'),_PathCard(path:_dbPath??'Not available'),
    const SizedBox(height:16),_SectionTitle('Attachments Storage'),_BodyText('Photos and documents attached to records are stored separately in the app documents folder.'),_PathCard(path:_attachmentPath??'Not available'),
    const SizedBox(height:16),const _BodyText('These figures cover the database file and the app attachment folder only. They do not include temporary files, cached files or backups exported to another location. Storage details are read-only here; no files are deleted from this screen.'),
  ]));
}
class _PathCard extends StatelessWidget{final String path;const _PathCard({required this.path});@override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:SelectableText(path,style:Theme.of(context).textTheme.bodySmall)));}
class _SectionTitle extends StatelessWidget{final String text;const _SectionTitle(this.text);@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(top:14,bottom:7),child:Text(text,style:Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight:FontWeight.w800)));}
class _BodyText extends StatelessWidget{final String text;const _BodyText(this.text);@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Text(text,style:Theme.of(context).textTheme.bodyMedium?.copyWith(height:1.5)));}
class _InfoLine extends StatelessWidget{final String label,value;const _InfoLine(this.label,this.value);@override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.symmetric(vertical:5),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Expanded(child:Text(label,style:const TextStyle(fontWeight:FontWeight.w600))),const SizedBox(width:12),Expanded(child:Text(value,textAlign:TextAlign.end))]));}
class _BulletList extends StatelessWidget{final List<String> items;const _BulletList(this.items);@override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:items.map((s)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(appText(context, "•  ", "•  ")),Expanded(child:Text(s))]))).toList());}
