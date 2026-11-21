import 'package:my_finance/core/preferences/sound_settings_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';
import 'package:my_finance/core/services/app_refresh_service.dart';
import 'package:my_finance/core/currency/currency_catalog.dart';
import 'package:intl/intl.dart';

import 'package:my_finance/core/localization/app_text.dart';
import 'package:my_finance/core/theme/app_colors.dart';
import 'package:my_finance/core/database/finance_database.dart';
import 'package:my_finance/shared/widgets/shared_app_bar_actions.dart';
import 'package:my_finance/features/finance/screens/transactions_screen.dart';

// Wallet ke options
// ============================================================

const List<String> walletTypes = [
  'Cash',
  'Bank',
  'Credit Card',
  'Debit Card',
  'Digital Wallet',
  'Investment',
  'Other',
  'Custom',
];

const List<IconData> walletIcons = [
  Icons.account_balance_wallet_outlined,
  Icons.account_balance_outlined,
  Icons.savings_outlined,
  Icons.credit_card_outlined,
  Icons.money_outlined,
  Icons.phone_android_outlined,
  Icons.trending_up_outlined,
  Icons.attach_money,
  Icons.payments_outlined,
  Icons.wallet_outlined,
  Icons.business_center_outlined,
  Icons.shopping_bag_outlined,
  Icons.currency_exchange_outlined,
  Icons.home_work_outlined,
  Icons.storefront_outlined,
  Icons.local_atm_outlined,
];

// ============================================================
// Wallets ka safha
// ============================================================

class _WalletWavePainter extends CustomPainter {
  final Color color;
  const _WalletWavePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width, 0);
    canvas.scale(-1, 1);

    Path wave(double offset) => Path()
      ..moveTo(0, size.height * 0.43 + offset + 1.0)
      ..quadraticBezierTo(size.width * 0.28, size.height * 0.03 - offset, size.width * 0.52, size.height * 0.43)
      ..quadraticBezierTo(size.width * 0.78, size.height * 0.88 + offset, size.width, size.height * 0.20)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave(2), Paint()..color = color.withValues(alpha: 0.22));
    canvas.drawPath(wave(0), Paint()..color = color.withValues(alpha: 0.55));
    canvas.drawPath(wave(-2), Paint()..color = color);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _WalletWavePainter oldDelegate) => oldDelegate.color != color;
}

class _BankCardPatternPainter extends CustomPainter {
  final int pattern;
  final Color color;
  final String design;
  const _BankCardPatternPainter({required this.pattern, required this.color, this.design = ''});

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()..color = color.withValues(alpha: 0.25)..style = PaintingStyle.stroke..strokeWidth = 1.15;
    final fill = Paint()..color = color.withValues(alpha: 0.12)..style = PaintingStyle.fill;
    final w = size.width, h = size.height;
    final path = Path();
    switch (design) {
      case 'ubl':
        // UBL's deep-blue face, white wordmark area and curved cyan sweep.
        final cyan=Paint()..color=const Color(0xFF00A6E8).withValues(alpha:.95);
        path..reset()..moveTo(0,h*.38)..cubicTo(w*.28,h*.56,w*.62,h*.48,w,h*.62)..lineTo(w,h*.78)..cubicTo(w*.62,h*.62,w*.28,h*.74,0,h*.55)..close();
        canvas.drawPath(path,cyan);
        canvas.drawLine(Offset(w*.08,h*.17),Offset(w*.48,h*.17),stroke);
        break;
      case 'mcb':
        // MCB's Visa family: black city-silhouette premium face with gold/silver variants.
        final skyline=Paint()..color=const Color(0xFFE3E6EA).withValues(alpha:.7);
        final buildings=[(0.40,.48,.06,.30),(0.47,.40,.08,.38),(0.56,.51,.06,.27),(0.63,.35,.08,.43),(0.72,.45,.07,.33),(0.81,.39,.06,.39),(0.89,.50,.07,.28)];
        for(final b in buildings) {
          final rect=Rect.fromLTWH(w*b.$1,h*b.$2,w*b.$3,h*b.$4);
          canvas.drawRect(rect,skyline);
          for(var y=rect.top+5;y<rect.bottom-3;y+=8) canvas.drawLine(Offset(rect.left+3,y),Offset(rect.right-3,y),stroke);
        }
        canvas.drawRect(Rect.fromLTWH(w*.37,h*.81,w*.58,h*.012),skyline);
        break;
      case 'hbl':
        // HBL's dark World/Gold card family: fine interlocking geometric lattice.
        for (var x = -h; x < w + h; x += 19) {
          path.reset();
          path.moveTo(x, 0); path.lineTo(x + h * .48, h * .5); path.lineTo(x, h);
          path.moveTo(x + 9, 0); path.lineTo(x + h * .48 + 9, h * .5); path.lineTo(x + 9, h);
          canvas.drawPath(path, stroke);
        }
        break;
      case 'allied':
        // Brushed silver field with layered angular graphite panels and orange edge.
        final p = Paint()..color = const Color(0xFF263442).withValues(alpha: .16);
        final p2 = Paint()..color = const Color(0xFFF58220).withValues(alpha: .92);
        path..moveTo(w*.42,0)..lineTo(w,0)..lineTo(w,h*.45)..lineTo(w*.62,h)..lineTo(w*.15,h)..close();
        canvas.drawPath(path,p);
        path..reset()..moveTo(w*.55,0)..lineTo(w,0)..lineTo(w,h*.18)..lineTo(w*.72,h*.42)..close();
        canvas.drawPath(path,stroke);
        path..reset()..moveTo(0,h*.78)..lineTo(w*.42,h*.16)..lineTo(w*.58,h*.2)..lineTo(w*.12,h)..lineTo(0,h)..close();
        canvas.drawPath(path,p);
        canvas.drawRect(Rect.fromLTWH(0,h*.84, w*.035,h*.16),p2);
        break;
      case 'meezan':
        // Dark premium face with fine gold Islamic star-and-tessellation motif.
        final gold = Paint()..color = const Color(0xFFD5B66B).withValues(alpha:.34)..style=PaintingStyle.stroke..strokeWidth=1;
        for (var row=-1; row<5; row++) {
          for (var col=0; col<8; col++) {
            final x=col*28.0+(row.isOdd?14:0)+w*.38, y=row*25.0;
            path..reset()..moveTo(x+14,y)..lineTo(x+28,y+12.5)..lineTo(x+14,y+25)..lineTo(x,y+12.5)..close();
            canvas.drawPath(path,gold);
            canvas.drawCircle(Offset(x+14,y+12.5),5,gold);
          }
        }
        break;
      case 'alfalah':
        // Bank Alfalah grey/black world-map-inspired face and red folded geometry.
        final map = Paint()..color=const Color(0xFFBFC2C5).withValues(alpha:.16);
        for (var i=0;i<5;i++) {
          canvas.drawOval(Rect.fromCenter(center:Offset(w*.35+i*9,h*.54),width:48+i*8,height:25+i*5),map);
        }
        final red=Paint()..color=const Color(0xFFD71935).withValues(alpha:.94);
        path..reset()..moveTo(w*.54,0)..lineTo(w,0)..lineTo(w,h*.72)..lineTo(w*.69,h*.44)..close();
        canvas.drawPath(path,red);
        path..reset()..moveTo(w*.48,h*.1)..lineTo(w*.7,h*.44)..lineTo(w*.55,h*.51)..lineTo(w*.36,h*.22)..close();
        canvas.drawPath(path,red);
        break;
      case 'askari':
        // Askari's navy constellation / connected-dot visual.
        final dot=Paint()..color=const Color(0xFFB7D9E8).withValues(alpha:.72);
        for(var row=0;row<7;row++) {
          for(var col=0;col<12;col++) {
            final x=w*.48+col*14.0+(row.isOdd?7:0), y=row*13.0+3;
            canvas.drawCircle(Offset(x,y),1.5+(col%3)*.45,dot);
            if(col<11) canvas.drawLine(Offset(x,y),Offset(x+14,y+7),stroke);
          }
        }
        break;
      case 'faysal':
        // Faysal Islami: deep teal field with interlocking Islamic geometry.
        final teal=Paint()..color=const Color(0xFF4DB7A7).withValues(alpha:.32)..style=PaintingStyle.stroke..strokeWidth=1.2;
        for(var row=-1;row<6;row++) {
          for(var col=0;col<9;col++) {
            final x=col*25.0+(row.isOdd?12.5:0)+w*.34, y=row*22.0;
            path..reset()..moveTo(x+12.5,y)..lineTo(x+25,y+11)..lineTo(x+12.5,y+22)..lineTo(x,y+11)..close();
            canvas.drawPath(path,teal);
            canvas.drawLine(Offset(x,y+11),Offset(x+25,y+11),teal);
          }
        }
        break;
      case 'bankislami':
        // Minimal matte-black titanium face with restrained curved silver lines.
        final silver=Paint()..color=const Color(0xFFE6E6E6).withValues(alpha:.18)..style=PaintingStyle.stroke..strokeWidth=1.1;
        for(var i=0;i<6;i++) {
          path..reset()..moveTo(-w*.1,h*(.12+i*.14))..cubicTo(w*.25,h*(.02+i*.14),w*.42,h*(.28+i*.14),w*.7,h*(.12+i*.14));
          canvas.drawPath(path,silver);
        }
        break;
      case 'habibmetro':
        // HabibMetro's emerald/gold/black faceted triangular tessellation.
        final colors=[const Color(0xFF00A078),const Color(0xFFD2A63B),const Color(0xFF101820)];
        for(var row=0;row<5;row++) {
          for(var col=0;col<9;col++) {
            final x=col*35.0+(row.isOdd?17.5:0)+w*.36,y=row*28.0;
            path..reset()..moveTo(x,y)..lineTo(x+35,y+14)..lineTo(x,y+28)..close();
            canvas.drawPath(path,Paint()..color=colors[(row+col)%3].withValues(alpha:.28));
            canvas.drawPath(path,stroke);
          }
        }
        break;
      case 'bop':
        final orange=Paint()..color=const Color(0xFFF58220).withValues(alpha:.72)..style=PaintingStyle.stroke..strokeWidth=5;
        for(var i=0;i<5;i++) canvas.drawCircle(Offset(w*.88,h*.48),18+i*17,orange);
        path..reset()..moveTo(w*.42,h)..cubicTo(w*.62,h*.55,w*.78,h*.9,w*1.08,h*.3);
        canvas.drawPath(path,Paint()..color=const Color(0xFFF58220).withValues(alpha:.38)..style=PaintingStyle.stroke..strokeWidth=8);
        break;
      case 'bok':
        final blue=Paint()..color=const Color(0xFF1F4E79).withValues(alpha:.18);
        path..moveTo(w*.6,0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*.28,h)..close();
        canvas.drawPath(path,blue);
        canvas.drawCircle(Offset(w*.78,h*.52),h*.35,stroke);
        break;
      case 'jsbank':
        final gold=Paint()..color=const Color(0xFFD5A64A).withValues(alpha:.8);
        for(var i=0;i<4;i++) {
          path..reset()..moveTo(w*(.44+i*.1),0)..lineTo(w*(.58+i*.1),0)..lineTo(w*(.2+i*.1),h)..lineTo(w*(.06+i*.1),h)..close();
          canvas.drawPath(path,Paint()..color=gold.color.withValues(alpha:.12));
          canvas.drawPath(path,stroke);
        }
        break;
      case 'nbp':
        final silver=Paint()..color=const Color(0xFFD5DADF).withValues(alpha:.2)..style=PaintingStyle.stroke..strokeWidth=1;
        for(var i=0;i<8;i++) {
          path..reset()..moveTo(w*.42+i*13.0,0)..lineTo(w*.82+i*13.0,h*.5)..lineTo(w*.42+i*13.0,h);
          canvas.drawPath(path,silver);
        }
        break;
      case 'sc':
        final blue=Paint()..color=const Color(0xFF00A6A0).withValues(alpha:.25);
        path..moveTo(w*.55,0)..lineTo(w,0)..lineTo(w,h)..lineTo(w*.75,h)..close();
        canvas.drawPath(path,blue);
        path..reset()..moveTo(w*.72,h*.1)..lineTo(w*.95,h*.5)..lineTo(w*.72,h*.9)..lineTo(w*.57,h*.5)..close();
        canvas.drawPath(path,stroke);
        break;
      case 'soneri':
        final green=Paint()..color=const Color(0xFFB3C86B).withValues(alpha:.28);
        for(var i=0;i<5;i++) {
          path..reset()..moveTo(w*.48+i*16,0)..lineTo(w*.72+i*16,h*.5)..lineTo(w*.48+i*16,h)..lineTo(w*.24+i*16,h*.5)..close();
          canvas.drawPath(path,green);
          canvas.drawPath(path,stroke);
        }
        break;
      default:
        switch (pattern % 6) {
          case 0:
            for (var i=-h;i<w+h;i+=18) canvas.drawLine(Offset(i.toDouble(),0),Offset(i+h,h),stroke);
            break;
          case 1:
            for(var i=0;i<5;i++) {
              final r=Rect.fromLTWH(w*.48+i*13,-h*.45+i*13,h*.9,h*.9);
              path..reset()..moveTo(r.center.dx,r.top)..lineTo(r.right,r.center.dy)..lineTo(r.center.dx,r.bottom)..lineTo(r.left,r.center.dy)..close();
              canvas.drawPath(path,stroke);
            }
            break;
          case 2:
            for(var i=0;i<7;i++) canvas.drawCircle(Offset(w*.82,h*.48),18.0+i*12,stroke);
            break;
          case 3:
            for(var row=-1;row<5;row++) for(var col=0;col<8;col++) {
              final side=22.0,x=col*side*1.5+(row.isOdd?side*.75:0),y=row*side*1.3;
              path..reset()..moveTo(x+side*.5,y)..lineTo(x+side,y+side*.25)..lineTo(x+side,y+side*.75)..lineTo(x+side*.5,y+side)..lineTo(x,y+side*.75)..lineTo(x,y+side*.25)..close();
              canvas.drawPath(path,stroke);
            }
            break;
          case 4:
            for(var i=0;i<6;i++) { path..reset()..moveTo(w*.35,h*(.15+i*.16))..cubicTo(w*.58,h*(.02+i*.16),w*.72,h*(.28+i*.16),w*1.05,h*(.1+i*.16)); canvas.drawPath(path,stroke); }
            break;
          case 5:
            for(var row=0;row<8;row++) for(var col=0;col<13;col++) canvas.drawCircle(Offset(col*18.0+5,row*15.0+5),1.7,fill);
            break;
        }
    }
  }

  @override
  bool shouldRepaint(covariant _BankCardPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color || oldDelegate.design != design;
}
class WalletsPage extends StatefulWidget {
  const WalletsPage({super.key});

  @override
  State<WalletsPage> createState() => _WalletsPageState();
}

class _WalletsPageState extends State<WalletsPage> {
  List<Map<String, dynamic>> wallets = [];
  bool loading = true;
  bool hideBalances = false;
  String numberFormat = '1,234.56';
  Set<int> _hiddenWalletIds = {}; 
  List<int> _walletOrder = [];
  bool _usePremiumCards = false;
  final Map<String, Map<String, dynamic>> _globalVerifiedCardThemes = {};

  @override
  void initState() {
    super.initState();
    GeneralPreferences.instance.revision.addListener(_onPreferencesChanged);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _loadGlobalCardCatalog();
    loadWallets();
  }

  void _onAppDataChanged() {
    if (mounted) loadWallets();
  }

  void _onPreferencesChanged() {
    if (mounted) loadWallets();
  }

  @override
  void dispose() {
    GeneralPreferences.instance.revision.removeListener(_onPreferencesChanged);
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    super.dispose();
  }

  Future<void> loadWallets() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final hide = await GeneralPreferences.instance.hideBalances;
      final format = await GeneralPreferences.instance.numberFormat;
      final result = List<Map<String, dynamic>>.from(
        await FinanceDB.instance.getWallets(),
      );
      final settings = await FinanceDB.instance.db.query(
        'app_settings',
        where: 'setting_key IN (?, ?)',
        whereArgs: ['hidden_wallet_ids', 'wallet_display_order'],
      );
      final values = {
        for (final row in settings)
          row['setting_key'].toString(): row['setting_value']?.toString() ?? ''
      };
      Set<int> hidden = {};
      List<int> order = [];
      try {
        hidden = (jsonDecode(values['hidden_wallet_ids'] ?? '[]') as List)
            .map((e) => (e as num).toInt()).toSet();
      } catch (_) {}
      try {
        order = (jsonDecode(values['wallet_display_order'] ?? '[]') as List)
            .map((e) => (e as num).toInt()).toList();
      } catch (_) {}
      result.removeWhere((w) => hidden.contains((w['id'] as num).toInt()));
      result.sort((a, b) {
        final ai = order.indexOf((a['id'] as num).toInt());
        final bi = order.indexOf((b['id'] as num).toInt());
        if (ai < 0 && bi < 0) return 0;
        if (ai < 0) return 1;
        if (bi < 0) return -1;
        return ai.compareTo(bi);
      });
      if (!mounted) return;
      setState(() {
        wallets = result;
        _hiddenWalletIds = hidden;
        _walletOrder = order;
        hideBalances = hide;
        numberFormat = format;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wallets load nahi ho sake: ${e.toString()}')),
      );
    }
  }

  String formatMoney(double amount, String currency) {
    if (hideBalances) return '$currency ******';
    final locale = numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return '$currency ${NumberFormat('#,##0.00', locale).format(amount)}';
  }

  Future<void> openWalletForm([
    Map<String, dynamic>? wallet,
  ]) async {
    // Wallet ka form aik behtar bottom sheet mein kholta hai.
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WalletFormDialog(wallet: wallet),
    );

    if (saved == true) {
      await loadWallets();
    }
  }

  Future<void> deleteWallet(Map<String, dynamic> wallet) async {
    final requireConfirmation = await GeneralPreferences.instance.deleteConfirmation;
    final confirmed = requireConfirmation ? await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(appText(context, 'Delete Wallet?', 'والٹ حذف کریں؟')),
        content: Text(
          'Kya aap "${wallet['name']}" wallet delete karna chahte hain?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(appText(context, 'Cancel', 'منسوخ کریں')), 
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(appText(context, 'Delete', 'حذف کریں')), 
          ),
        ],
      ),
    ) : true;

    if (confirmed != true) return;

    try {
      await SoundSettingsService.instance.play('delete_warning');
      await FinanceDB.instance.deleteWallet(wallet['id'] as int);
      await SoundSettingsService.instance.play('delete_success');
      if (await GeneralPreferences.instance.hapticFeedback) {
        await HapticFeedback.selectionClick();
      }
      await loadWallets();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    }
  }

  // Bank-specific ATM-card themes. Names and aliases cover SBP-regulated
  // commercial, Islamic, digital, foreign and specialized banks in Pakistan.
  Future<void> _loadGlobalCardCatalog() async {
    const cacheKey = 'global_card_catalog_cache_v1';
    const catalogUrl = 'https://raw.githubusercontent.com/shahidlaashary/my-finance-android/main/assets/data/global_card_catalog.json';
    String? raw;
    try {
      final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      try {
        final request = await client.getUrl(Uri.parse(catalogUrl)).timeout(const Duration(seconds: 7));
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close().timeout(const Duration(seconds: 7));
        if (response.statusCode == HttpStatus.ok) {
          final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 7));
          if (body.length <= 2000000) {
            final decoded = jsonDecode(body);
            if (decoded is Map && decoded['schemaVersion'] == 1 && decoded['records'] is List) {
              raw = body;
              await (await SharedPreferences.getInstance()).setString(cacheKey, body);
            }
          }
        }
      } finally { client.close(force: true); }
    } catch (_) {}
    if (raw == null) {
      try { raw = (await SharedPreferences.getInstance()).getString(cacheKey); } catch (_) {}
    }
    if (raw == null) {
      try { raw = await rootBundle.loadString('assets/data/global_card_catalog.json'); } catch (_) {}
    }
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final records = (decoded['records'] as List? ?? const []);
      final loaded = <String, Map<String, dynamic>>{};
      for (final value in records) {
        if (value is! Map) continue;
        final record = Map<String, dynamic>.from(value);
        final status = (record['verificationStatus'] ?? 'unverified').toString();
        if (status != 'official_card_verified' && status != 'bank_branding_verified') continue;
        final primary = (record['primaryColor'] ?? '').toString();
        final secondary = (record['secondaryColor'] ?? '').toString();
        if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(primary) ||
            !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(secondary)) continue;
        final theme = <String, dynamic>{
          'brand': (record['brandName'] ?? record['institutionName'] ?? '').toString().toUpperCase(),
          'mark': (record['shortName'] ?? record['institutionName'] ?? '').toString().toUpperCase(),
          'colors': [
            Color(int.parse(primary.substring(1), radix: 16) | 0xFF000000),
            Color(int.parse(secondary.substring(1), radix: 16) | 0xFF000000),
          ],
          'pattern': 2,
          'isKnown': true,
          'verificationStatus': status,
          'sourceUrl': (record['sourceUrl'] ?? record['officialWebsite'] ?? '').toString(),
        };
        final names = <String>[
          (record['institutionName'] ?? '').toString(),
          ...((record['aliases'] as List? ?? const []).map((e) => e.toString())),
        ];
        for (final candidate in names) {
          final key = candidate.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (key.isNotEmpty) loaded[key] = theme;
        }
      }
      if (!mounted || loaded.isEmpty) return;
      setState(() {
        _globalVerifiedCardThemes..clear()..addAll(loaded);
      });
    } catch (_) {}
  }

  Map<String, dynamic> _bankCardTheme(String bankName) {
    final name = bankName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final catalogTheme = _globalVerifiedCardThemes[name];
    if (catalogTheme != null) return catalogTheme;
    // Easypaisa Digital Bank is a licensed bank; keep it distinct from the
    // Easypaisa wallet brand when the user enters the full bank name.
    if (name.contains('easypaisadigitalbank') || name.contains('easypaisabank')) {
      return {
        'brand': 'EASYPAISA BANK',
        'mark': 'EP',
        'colors': [const Color(0xFF16864B), const Color(0xFF75B843)],
        'pattern': 3,
        'isKnown': true,
      };
    }
    final themes = <Map<String, dynamic>>[
      {'keys': ['easypaisa', 'easypaisadigitalbank'], 'brand': 'EASYPAISA', 'mark': 'EASYPAISA', 'design': 'easypaisa', 'colors': [const Color(0xFF087A3E), const Color(0xFF62B447)]},
      {'keys': ['jazzcash', 'mobilinkwallet'], 'brand': 'JAZZCASH', 'mark': 'JAZZ', 'design': 'jazzcash', 'colors': [const Color(0xFF8B1238), const Color(0xFFE04462)]},
      {'keys': ['nayapay', 'naya'], 'brand': 'NAYAPAY', 'mark': 'NAYA', 'design': 'nayapay', 'colors': [const Color(0xFF143D79), const Color(0xFF3C8FD0)]},
      {'keys': ['sadapay', 'sada'], 'brand': 'SADAPAY', 'mark': 'SADA', 'design': 'sadapay', 'colors': [const Color(0xFF24272D), const Color(0xFF68717C)]},
      {'keys': ['zindigi', 'jszindigi'], 'brand': 'ZINDIGI', 'mark': 'ZINDIGI', 'design': 'zindigi', 'colors': [const Color(0xFF39206D), const Color(0xFF8D55D6)]},
      {'keys': ['upaisa'], 'brand': 'UPAISA', 'mark': 'UPAISA', 'design': 'upaisa', 'colors': [const Color(0xFF542B83), const Color(0xFF9A68C5)]},
      {'keys': ['hblkonnect', 'konnectbyhbl'], 'brand': 'HBL KONNECT', 'mark': 'KONNECT', 'colors': [const Color(0xFF087B55), const Color(0xFF58B28C)]},
      {'keys': ['ublomni', 'omniubl'], 'brand': 'UBL OMNI', 'mark': 'OMNI', 'colors': [const Color(0xFF54247A), const Color(0xFF9A4CBA)]},
      {'keys': ['alfalahalfa', 'alfadigital', 'alfaapp'], 'brand': 'ALFA BY BANK ALFALAH', 'mark': 'ALFA', 'colors': [const Color(0xFF8D1828), const Color(0xFFD44A55)]},
      {'keys': ['keenu'], 'brand': 'KEENU', 'mark': 'KEENU', 'colors': [const Color(0xFF176B9B), const Color(0xFF53A5C8)]},
      {'keys': ['simsim'], 'brand': 'SIMSIM', 'mark': 'SIMSIM', 'colors': [const Color(0xFF087A4B), const Color(0xFF63B487)]},
      {'keys': ['alliedbank', 'allied', 'abl'], 'brand': 'ALLIED BANK', 'mark': 'ALLIED', 'design': 'allied', 'colors': [const Color(0xFFD9DADD), const Color(0xFF7F858D)]},
      {'keys': ['habibbanklimited', 'habibbank', 'hbl'], 'brand': 'HBL', 'mark': 'HBL', 'design': 'hbl', 'colors': [const Color(0xFF090B10), const Color(0xFF34302A)]},
      {'keys': ['meezanbank', 'meezan'], 'brand': 'MEEZAN BANK', 'mark': 'MEEZAN', 'design': 'meezan', 'colors': [const Color(0xFF11131B), const Color(0xFF302C28)]},
      {'keys': ['unitedbank', 'ubl'], 'brand': 'UBL', 'mark': 'UBL', 'design': 'ubl', 'colors': [const Color(0xFF06265B), const Color(0xFF07549A)]},
      {'keys': ['mcbislamicbank', 'mcbislamic'], 'brand': 'MCB ISLAMIC', 'mark': 'MCB', 'colors': [const Color(0xFF087B65), const Color(0xFF42B99B)]},
      {'keys': ['mcb', 'muslimcommercialbank'], 'brand': 'MCB BANK', 'mark': 'MCB', 'design': 'mcb', 'colors': [const Color(0xFF111B2B), const Color(0xFF303D50)]},
      {'keys': ['bankalfalah', 'alfalah'], 'brand': 'BANK ALFALAH', 'mark': 'ALFALAH', 'design': 'alfalah', 'colors': [const Color(0xFF333438), const Color(0xFF85878A)]},
      {'keys': ['bankalhabib', 'alhabib', 'bahl'], 'brand': 'BANK AL HABIB', 'mark': 'BAH', 'colors': [const Color(0xFF7B202B), const Color(0xFFBD4D54)]},
      {'keys': ['askaribank', 'askari'], 'brand': 'ASKARI BANK', 'mark': 'ASKARI', 'design': 'askari', 'colors': [const Color(0xFF080F35), const Color(0xFF222A57)]},
      {'keys': ['faysalbank', 'faysal'], 'brand': 'FAYSAL BANK', 'mark': 'FAYSAL', 'design': 'faysal', 'colors': [const Color(0xFF062D35), const Color(0xFF075B5B)]},
      {'keys': ['nationalbankofpakistan', 'nationalbank', 'nbp'], 'brand': 'NBP', 'mark': 'NBP', 'design': 'nbp', 'colors': [const Color(0xFF11151B), const Color(0xFF414951)]},
      {'keys': ['bankofpunjab', 'thebankofpunjab', 'bop'], 'brand': 'THE BANK OF PUNJAB', 'mark': 'BOP', 'design': 'bop', 'colors': [const Color(0xFF111E32), const Color(0xFF253B58)]},
      {'keys': ['sindhbank'], 'brand': 'SINDH BANK', 'mark': 'SINDH', 'design': 'sc', 'colors': [const Color(0xFF123B68), const Color(0xFF247A94)]},
      {'keys': ['bankofkhyber', 'bok'], 'brand': 'BANK OF KHYBER', 'mark': 'BOK', 'design': 'bok', 'colors': [const Color(0xFFE1E4E8), const Color(0xFFB7C0CB)]},
      {'keys': ['firstwomenbank', 'fwb'], 'brand': 'FIRST WOMEN BANK', 'mark': 'FWB', 'colors': [const Color(0xFF813D78), const Color(0xFFC16AA8)]},
      {'keys': ['bankislami', 'bankislamiPakistan'], 'brand': 'BANKISLAMI', 'mark': 'BANKISLAMI', 'design': 'bankislami', 'colors': [const Color(0xFF08090B), const Color(0xFF292B2F)]},
      {'keys': ['dubaiislamicbank', 'dibpak', 'dib'], 'brand': 'DUBAI ISLAMIC BANK', 'mark': 'DIB', 'colors': [const Color(0xFF087E78), const Color(0xFF45B8A7)]},
      {'keys': ['albarakabank', 'albaraka'], 'brand': 'AL BARAKA BANK', 'mark': 'AB', 'colors': [const Color(0xFF245B48), const Color(0xFF70A77A)]},
      {'keys': ['habibmetropolitan', 'habibmetro', 'hmb'], 'brand': 'HABIBMETRO', 'mark': 'HABIBMETRO', 'design': 'habibmetro', 'colors': [const Color(0xFF062E2A), const Color(0xFF155C4A)]},
      {'keys': ['jsbank', 'jsbl'], 'brand': 'JS BANK', 'mark': 'JS BANK', 'design': 'jsbank', 'colors': [const Color(0xFF24262C), const Color(0xFF5D6066)]},
      {'keys': ['soneribank', 'soneri'], 'brand': 'SONERI BANK', 'mark': 'SONERI', 'design': 'soneri', 'colors': [const Color(0xFF151A23), const Color(0xFF414C5D)]},
      {'keys': ['standardchartered', 'scpakistan'], 'brand': 'STANDARD CHARTERED', 'mark': 'SC', 'design': 'sc', 'colors': [const Color(0xFF006B68), const Color(0xFF42A69A)]},
      {'keys': ['sambabank', 'samba'], 'brand': 'SAMBA BANK', 'mark': 'SAM', 'colors': [const Color(0xFF174D86), const Color(0xFF4D91C9)]},
      {'keys': ['bankmakramah', 'makramah', 'summitbank'], 'brand': 'BANK MAKRAMAH', 'mark': 'BM', 'colors': [const Color(0xFF633B80), const Color(0xFFA77BC0)]},
      {'keys': ['easypaisabank', 'easypaisa'], 'brand': 'EASYPAISA BANK', 'mark': 'EP', 'colors': [const Color(0xFF16864B), const Color(0xFF75B843)]},
      {'keys': ['mashreqbank', 'mashreq'], 'brand': 'MASHREQ', 'mark': 'MB', 'colors': [const Color(0xFF1B4C91), const Color(0xFF4A8BD0)]},
      {'keys': ['raqami', 'raqamidigital'], 'brand': 'RAQAMI', 'mark': 'RD', 'colors': [const Color(0xFF007A75), const Color(0xFF43B5A2)]},
      {'keys': ['zaraitaraqiati', 'ztbl'], 'brand': 'ZTBL', 'mark': 'ZT', 'colors': [const Color(0xFF28613D), const Color(0xFF75A85B)]},
      {'keys': ['punjabprovincialcooperative', 'ppcbl'], 'brand': 'PUNJAB PROVINCIAL CO-OP', 'mark': 'PPC', 'colors': [const Color(0xFF245A8C), const Color(0xFF5A9CC7)]},
      {'keys': ['smebank'], 'brand': 'SME BANK', 'mark': 'SME', 'colors': [const Color(0xFF3C536D), const Color(0xFF7895B0)]},
      {'keys': ['bankofchina', 'boc'], 'brand': 'BANK OF CHINA', 'mark': 'BOC', 'colors': [const Color(0xFF9D1828), const Color(0xFFE04B50)]},
      {'keys': ['citibank', 'citi'], 'brand': 'CITI', 'mark': 'CITI', 'colors': [const Color(0xFF07539A), const Color(0xFF3989C9)]},
      {'keys': ['deutschebank', 'deutsche'], 'brand': 'DEUTSCHE BANK', 'mark': 'DB', 'colors': [const Color(0xFF173B78), const Color(0xFF547BB7)]},
      {'keys': ['icbc', 'industrialcommercialbankofchina'], 'brand': 'ICBC', 'mark': 'ICBC', 'colors': [const Color(0xFF9A1725), const Color(0xFFD64B4E)]},
      {'keys': ['silkbank', 'silk'], 'brand': 'SILKBANK', 'mark': 'SB', 'colors': [const Color(0xFF6B397E), const Color(0xFFB17BBE)]},
      {'keys': ['khushhalimicrofinance', 'khushhali'], 'brand': 'KHUSHHALI BANK', 'mark': 'KB', 'colors': [const Color(0xFF176C4C), const Color(0xFF65A96C)]},
      {'keys': ['mobilinkmicrofinance', 'jazzcash', 'mobilink'], 'brand': 'MOBILINK MICROFINANCE', 'mark': 'MM', 'colors': [const Color(0xFF8C1D48), const Color(0xFFD84B73)]},
      {'keys': ['ubank', 'umicrofinance'], 'brand': 'U MICROFINANCE BANK', 'mark': 'U', 'colors': [const Color(0xFF385E9B), const Color(0xFF78A6D5)]},
      {'keys': ['nrsp'], 'brand': 'NRSP MICROFINANCE', 'mark': 'NR', 'colors': [const Color(0xFF35633D), const Color(0xFF86AD5E)]},
      {'keys': ['advans'], 'brand': 'ADVANS MICROFINANCE', 'mark': 'A', 'colors': [const Color(0xFF315A84), const Color(0xFF77A5C8)]},
      {'keys': ['hblmicrofinance', 'hblmfb', 'firstmicrofinance'], 'brand': 'HBL MICROFINANCE', 'mark': 'HBL MFB', 'colors': [const Color(0xFF075C48), const Color(0xFF269B76)]},
      {'keys': ['apnamicrofinance', 'apnabank'], 'brand': 'APNA MICROFINANCE', 'mark': 'APNA', 'colors': [const Color(0xFF176A91), const Color(0xFF4AADD0)]},
      {'keys': ['halanmicrofinance', 'halan'], 'brand': 'HALAN BANK', 'mark': 'HALAN', 'colors': [const Color(0xFF252B58), const Color(0xFF5969A9)]},
      {'keys': ['lolcmicrofinance', 'lolc', 'pakomanmicrofinance'], 'brand': 'LOLC MICROFINANCE', 'mark': 'LOLC', 'colors': [const Color(0xFF174F83), const Color(0xFF4E91C5)]},
      {'keys': ['sindhmicrofinance'], 'brand': 'SINDH MICROFINANCE', 'mark': 'SMB', 'colors': [const Color(0xFF14577B), const Color(0xFF4A9DC1)]},
      {'keys': ['abhibank', 'abhimicrofinance', 'fincamicrofinance', 'finca'], 'brand': 'ABHI MICROFINANCE', 'mark': 'ABHI', 'colors': [const Color(0xFF4B2B71), const Color(0xFF9364B5)]},
      {'keys': ['asamicrofinance', 'asa'], 'brand': 'ASA MICROFINANCE', 'mark': 'ASA', 'colors': [const Color(0xFF146B69), const Color(0xFF4AA7A0)]},
      {'keys': ['telenormicrofinance', 'telenor'], 'brand': 'TELENOR MICROFINANCE', 'mark': 'TM', 'colors': [const Color(0xFF0876A8), const Color(0xFF43B4D4)]},

      // International bank themes follow the Pakistan-specific registry above.
      // Major international banks, grouped across the Americas, Europe, Middle East, Africa and Asia-Pacific.
      {'keys': ['jpmorganchase', 'chasebank', 'chase'], 'brand': 'CHASE', 'mark': 'CHASE', 'colors': [const Color(0xFF073B75), const Color(0xFF2784C7)]},
      {'keys': ['bankofamerica', 'bofa'], 'brand': 'BANK OF AMERICA', 'mark': 'BOA', 'colors': [const Color(0xFF092B61), const Color(0xFFB9273D)]},
      {'keys': ['wellsfargo'], 'brand': 'WELLS FARGO', 'mark': 'WF', 'colors': [const Color(0xFF9D1C28), const Color(0xFFE3A72F)]},
      {'keys': ['citibank', 'citi'], 'brand': 'CITI', 'mark': 'CITI', 'colors': [const Color(0xFF07539A), const Color(0xFF3989C9)]},
      {'keys': ['hsbc'], 'brand': 'HSBC', 'mark': 'HSBC', 'colors': [const Color(0xFFB51F2B), const Color(0xFF252B35)]},
      {'keys': ['barclays'], 'brand': 'BARCLAYS', 'mark': 'BARCLAYS', 'colors': [const Color(0xFF0072A8), const Color(0xFF42A8D1)]},
      {'keys': ['lloydsbank', 'lloyds'], 'brand': 'LLOYDS BANK', 'mark': 'LLOYDS', 'colors': [const Color(0xFF006A45), const Color(0xFF69A86B)]},
      {'keys': ['natwest'], 'brand': 'NATWEST', 'mark': 'NW', 'colors': [const Color(0xFF4B246D), const Color(0xFF9A6BB4)]},
      {'keys': ['royalbankofcanada', 'rbc'], 'brand': 'RBC', 'mark': 'RBC', 'colors': [const Color(0xFF0051A5), const Color(0xFF4A9BD8)]},
      {'keys': ['tdcanadatrust', 'tdbank'], 'brand': 'TD', 'mark': 'TD', 'colors': [const Color(0xFF167A45), const Color(0xFF64B879)]},
      {'keys': ['bankofmontreal', 'bmo'], 'brand': 'BMO', 'mark': 'BMO', 'colors': [const Color(0xFF0075A8), const Color(0xFF58A9CF)]},
      {'keys': ['scotiabank'], 'brand': 'SCOTIABANK', 'mark': 'SCOTIA', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE45A56)]},
      {'keys': ['commonwealthbank', 'commbank'], 'brand': 'COMMONWEALTH BANK', 'mark': 'CBA', 'colors': [const Color(0xFFE2B500), const Color(0xFF292D35)]},
      {'keys': ['westpac'], 'brand': 'WESTPAC', 'mark': 'WESTPAC', 'colors': [const Color(0xFFB52236), const Color(0xFFEA6871)]},
      {'keys': ['anzbank', 'anz'], 'brand': 'ANZ', 'mark': 'ANZ', 'colors': [const Color(0xFF0072AC), const Color(0xFF56B4D7)]},
      {'keys': ['nabnationalaustraliabank', 'nab'], 'brand': 'NAB', 'mark': 'NAB', 'colors': [const Color(0xFFC51F35), const Color(0xFFE66B70)]},
      {'keys': ['statebankofindia', 'sbi'], 'brand': 'STATE BANK OF INDIA', 'mark': 'SBI', 'colors': [const Color(0xFF176B9B), const Color(0xFF65B5D4)]},
      {'keys': ['hdfcbank', 'hdfc'], 'brand': 'HDFC BANK', 'mark': 'HDFC', 'colors': [const Color(0xFF004C8F), const Color(0xFF3E8BC5)]},
      {'keys': ['icicibank', 'icici'], 'brand': 'ICICI BANK', 'mark': 'ICICI', 'colors': [const Color(0xFF9B2738), const Color(0xFFE18A36)]},
      {'keys': ['axisbank', 'axis'], 'brand': 'AXIS BANK', 'mark': 'AXIS', 'colors': [const Color(0xFF6D1B70), const Color(0xFFB85CB2)]},
      // India: RBI-listed public and private sector banks, small finance banks and payments banks.
      {'keys': ['bankofbaroda', 'bobindia'], 'brand': 'BANK OF BARODA', 'mark': 'BOB', 'colors': [const Color(0xFFE86B24), const Color(0xFFF2A04A)]},
      {'keys': ['bankofindia', 'boiindia'], 'brand': 'BANK OF INDIA', 'mark': 'BOI', 'colors': [const Color(0xFF8B1E35), const Color(0xFFD05A66)]},
      {'keys': ['bankofmaharashtra', 'mahabank'], 'brand': 'BANK OF MAHARASHTRA', 'mark': 'BOM', 'colors': [const Color(0xFF8B1D35), const Color(0xFFD75A67)]},
      {'keys': ['canarabank', 'canara'], 'brand': 'CANARA BANK', 'mark': 'CANARA', 'colors': [const Color(0xFF087A4B), const Color(0xFF54B38A)]},
      {'keys': ['centralbankofindia', 'centralbankindia'], 'brand': 'CENTRAL BANK OF INDIA', 'mark': 'CBI', 'colors': [const Color(0xFF174A82), const Color(0xFF6096C5)]},
      {'keys': ['indianbank'], 'brand': 'INDIAN BANK', 'mark': 'IB', 'colors': [const Color(0xFF8A1E35), const Color(0xFFD45B68)]},
      {'keys': ['indianoverseasbank', 'iobindia'], 'brand': 'INDIAN OVERSEAS BANK', 'mark': 'IOB', 'colors': [const Color(0xFF087B55), const Color(0xFF58B28C)]},
      {'keys': ['punjabandsindbank', 'psbindia'], 'brand': 'PUNJAB & SIND BANK', 'mark': 'PSB', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['punjabnationalbank', 'pnbindia'], 'brand': 'PUNJAB NATIONAL BANK', 'mark': 'PNB', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['ucobank'], 'brand': 'UCO BANK', 'mark': 'UCO', 'colors': [const Color(0xFF174B85), const Color(0xFF6A9CC8)]},
      {'keys': ['unionbankofindia', 'unionbankindia'], 'brand': 'UNION BANK OF INDIA', 'mark': 'UBI', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['bandhanbank'], 'brand': 'BANDHAN BANK', 'mark': 'BANDHAN', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['csbbank', 'catholicsyrianbank'], 'brand': 'CSB BANK', 'mark': 'CSB', 'colors': [const Color(0xFF9B1F32), const Color(0xFFE36A70)]},
      {'keys': ['cityunionbank'], 'brand': 'CITY UNION BANK', 'mark': 'CUB', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['dhanlaxmibank'], 'brand': 'DHANLAXMI BANK', 'mark': 'DLB', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['federalbankindia', 'federalbank'], 'brand': 'FEDERAL BANK', 'mark': 'FEDERAL', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['indusindbank'], 'brand': 'INDUSIND BANK', 'mark': 'INDUSIND', 'colors': [const Color(0xFF8B1D35), const Color(0xFFD65A68)]},
      {'keys': ['idfcfirstbank', 'idfcfirst'], 'brand': 'IDFC FIRST BANK', 'mark': 'IDFC FIRST', 'colors': [const Color(0xFF9A1F35), const Color(0xFFE36A72)]},
      {'keys': ['jammuandkashmirbank', 'jkbindia'], 'brand': 'J&K BANK', 'mark': 'JKB', 'colors': [const Color(0xFF087A55), const Color(0xFF5AB58D)]},
      {'keys': ['karnatakabank'], 'brand': 'KARNATAKA BANK', 'mark': 'KBL', 'colors': [const Color(0xFF8B1D35), const Color(0xFFD65A68)]},
      {'keys': ['karurvysyabank'], 'brand': 'KARUR VYSYA BANK', 'mark': 'KVB', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['kotakmahindrabank', 'kotakbank'], 'brand': 'KOTAK MAHINDRA BANK', 'mark': 'KOTAK', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['nainitalbank'], 'brand': 'NAINITAL BANK', 'mark': 'NBL', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['rblbank'], 'brand': 'RBL BANK', 'mark': 'RBL', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['southindianbank'], 'brand': 'SOUTH INDIAN BANK', 'mark': 'SIB', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['tamilnadmercantilebank', 'tmbindia'], 'brand': 'TAMILNAD MERCANTILE BANK', 'mark': 'TMB', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['yesbank'], 'brand': 'YES BANK', 'mark': 'YES', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['idbibank'], 'brand': 'IDBI BANK', 'mark': 'IDBI', 'colors': [const Color(0xFF087A55), const Color(0xFF58B28C)]},
      {'keys': ['ausmallfinancebank', 'aubankindia'], 'brand': 'AU SMALL FINANCE BANK', 'mark': 'AU', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['capitalsmallfinancebank'], 'brand': 'CAPITAL SMALL FINANCE BANK', 'mark': 'CAPITAL', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['equitas'], 'brand': 'EQUITAS SMALL FINANCE BANK', 'mark': 'EQUITAS', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['esafsmallfinancebank', 'esafbank'], 'brand': 'ESAF SMALL FINANCE BANK', 'mark': 'ESAF', 'colors': [const Color(0xFF087A55), const Color(0xFF58B28C)]},
      {'keys': ['suryodaysmallfinancebank', 'suryodaybank'], 'brand': 'SURYODAY SMALL FINANCE BANK', 'mark': 'SURYODAY', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['ujjivansmallfinancebank', 'ujjivanbank'], 'brand': 'UJJIVAN SMALL FINANCE BANK', 'mark': 'UJJIVAN', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['utkarshsmallfinancebank', 'utkarshbank'], 'brand': 'UTKARSH SMALL FINANCE BANK', 'mark': 'UTKARSH', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['shivaliksmallfinancebank', 'shivalikbank'], 'brand': 'SHIVALIK SMALL FINANCE BANK', 'mark': 'SHIVALIK', 'colors': [const Color(0xFF087A55), const Color(0xFF58B28C)]},
      {'keys': ['unitysmallfinancebank', 'unitybankindia'], 'brand': 'UNITY SMALL FINANCE BANK', 'mark': 'UNITY', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['indiapostpaymentsbank', 'ippb'], 'brand': 'INDIA POST PAYMENTS BANK', 'mark': 'IPPB', 'colors': [const Color(0xFF8A1D35), const Color(0xFFD65A68)]},
      {'keys': ['finopaymentsbank', 'finobank'], 'brand': 'FINO PAYMENTS BANK', 'mark': 'FINO', 'colors': [const Color(0xFF087A55), const Color(0xFF58B28C)]},
      {'keys': ['airtelpaymentsbank'], 'brand': 'AIRTEL PAYMENTS BANK', 'mark': 'AIRTEL', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['nsdlpaymentsbank'], 'brand': 'NSDL PAYMENTS BANK', 'mark': 'NSDL', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['northeastsmallfinancebank', 'nesfbank'], 'brand': 'NORTH EAST SMALL FINANCE BANK', 'mark': 'NESFB', 'colors': [const Color(0xFF087A55), const Color(0xFF58B28C)]},
      {'keys': ['slicesmallfinancebank', 'slice'], 'brand': 'SLICE SMALL FINANCE BANK', 'mark': 'SLICE', 'colors': [const Color(0xFF24272D), const Color(0xFF68717C)]},

      {'keys': ['emiratesnbd', 'enbd'], 'brand': 'EMIRATES NBD', 'mark': 'ENBD', 'colors': [const Color(0xFF007D83), const Color(0xFF4DB8AD)]},
      {'keys': ['firstabudhabibank', 'fabuae', 'fab'], 'brand': 'FIRST ABU DHABI BANK', 'mark': 'FAB', 'colors': [const Color(0xFF173D70), const Color(0xFF4F83B8)]},
      {'keys': ['adcb', 'abudhabi commercial'], 'brand': 'ADCB', 'mark': 'ADCB', 'colors': [const Color(0xFFB32135), const Color(0xFFE46A72)]},
      {'keys': ['alrajhibank', 'alrajhi'], 'brand': 'AL RAJHI BANK', 'mark': 'ALRAJHI', 'colors': [const Color(0xFF08784E), const Color(0xFF62B58A)]},
      {'keys': ['saudinationalbank', 'snb'], 'brand': 'SAUDI NATIONAL BANK', 'mark': 'SNB', 'colors': [const Color(0xFF006B4F), const Color(0xFF58A98A)]},
      {'keys': ['riyadbank'], 'brand': 'RIYAD BANK', 'mark': 'RIYAD', 'colors': [const Color(0xFF006A50), const Color(0xFF65A98B)]},
      {'keys': ['bankdhaka', 'dutchbanglabank', 'dbbl'], 'brand': 'DUTCH-BANGLA BANK', 'mark': 'DBBL', 'colors': [const Color(0xFF176B9B), const Color(0xFF53A5C8)]},
      {'keys': ['bracbank', 'brac'], 'brand': 'BRAC BANK', 'mark': 'BRAC', 'colors': [const Color(0xFF8C1D35), const Color(0xFFD65B6B)]},
      {'keys': ['ziraatbank', 'ziraat'], 'brand': 'ZIRAAT BANK', 'mark': 'ZIRAAT', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE56B72)]},
      {'keys': ['isbank', 'isbankasi'], 'brand': 'ISBANK', 'mark': 'IS', 'colors': [const Color(0xFF0075A8), const Color(0xFF55B0D1)]},
      {'keys': ['bankofchina', 'boc'], 'brand': 'BANK OF CHINA', 'mark': 'BOC', 'colors': [const Color(0xFF9D1828), const Color(0xFFE04B50)]},
      {'keys': ['icbc', 'industrialcommercialbankofchina'], 'brand': 'ICBC', 'mark': 'ICBC', 'colors': [const Color(0xFF9A1725), const Color(0xFFD64B4E)]},
      {'keys': ['mufgbank', 'mitsubishiufj', 'mufg'], 'brand': 'MUFG BANK', 'mark': 'MUFG', 'colors': [const Color(0xFF8A1E2D), const Color(0xFFD65A62)]},
      {'keys': ['sumitomomitsui', 'smbc'], 'brand': 'SMBC', 'mark': 'SMBC', 'colors': [const Color(0xFF087B55), const Color(0xFF55B48A)]},
      {'keys': ['mizuhobank', 'mizuho'], 'brand': 'MIZUHO BANK', 'mark': 'MIZUHO', 'colors': [const Color(0xFF1E4B8F), const Color(0xFF6C91C5)]},
      {'keys': ['dbsbank', 'dbs'], 'brand': 'DBS', 'mark': 'DBS', 'colors': [const Color(0xFFE02B35), const Color(0xFFEF777B)]},
      {'keys': ['ocbcbank', 'ocbc'], 'brand': 'OCBC', 'mark': 'OCBC', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['unitedoverseasbank', 'uob'], 'brand': 'UOB', 'mark': 'UOB', 'colors': [const Color(0xFF173B78), const Color(0xFF547BB7)]},
      {'keys': ['maybank'], 'brand': 'MAYBANK', 'mark': 'MAYBANK', 'colors': [const Color(0xFFE2B500), const Color(0xFF333333)]},
      {'keys': ['bangkokbank'], 'brand': 'BANGKOK BANK', 'mark': 'BBL', 'colors': [const Color(0xFF1E4D8C), const Color(0xFF6C9AC8)]},
      {'keys': ['standardbank', 'standardbankgroup'], 'brand': 'STANDARD BANK', 'mark': 'SB', 'colors': [const Color(0xFF005A9C), const Color(0xFF55A0C9)]},
      {'keys': ['ecobank'], 'brand': 'ECOBANK', 'mark': 'ECO', 'colors': [const Color(0xFF007B60), const Color(0xFF54B39A)]},
      {'keys': ['bnpparibas', 'bnp'], 'brand': 'BNP PARIBAS', 'mark': 'BNP', 'colors': [const Color(0xFF087B55), const Color(0xFF58B28C)]},
      {'keys': ['societegenerale', 'socgen'], 'brand': 'SOCIETE GENERALE', 'mark': 'SG', 'colors': [const Color(0xFFE33A42), const Color(0xFF9E1D2C)]},
      {'keys': ['commerzbank'], 'brand': 'COMMERZBANK', 'mark': 'CB', 'colors': [const Color(0xFFE5A800), const Color(0xFF4A9B73)]},
      {'keys': ['sberbank'], 'brand': 'SBERBANK', 'mark': 'SBER', 'colors': [const Color(0xFF087C4B), const Color(0xFF5DBB8A)]},
      {'keys': ['vtbbank', 'vtb'], 'brand': 'VTB BANK', 'mark': 'VTB', 'colors': [const Color(0xFF1B4B85), const Color(0xFF6A96C4)]},
      {'keys': ['itau', 'itaubank'], 'brand': 'ITAU', 'mark': 'ITAU', 'colors': [const Color(0xFF164A91), const Color(0xFF5D91C8)]},
      {'keys': ['bradesco'], 'brand': 'BRADESCO', 'mark': 'BRA', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['bancodobrasil', 'bbbrasil'], 'brand': 'BANCO DO BRASIL', 'mark': 'BB', 'colors': [const Color(0xFF174C91), const Color(0xFFE0B32B)]},
      {'keys': ['bbva'], 'brand': 'BBVA', 'mark': 'BBVA', 'colors': [const Color(0xFF063B75), const Color(0xFF328BD0)]},
      {'keys': ['banorte'], 'brand': 'BANORTE', 'mark': 'BANORTE', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['bancolombia'], 'brand': 'BANCOLOMBIA', 'mark': 'BC', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE6A52C)]},
      {'keys': ['bancodechile'], 'brand': 'BANCO DE CHILE', 'mark': 'BDCH', 'colors': [const Color(0xFF174B85), const Color(0xFF6B9BC8)]},
      {'keys': ['bancogalicia', 'galicia'], 'brand': 'BANCO GALICIA', 'mark': 'GALICIA', 'colors': [const Color(0xFFE06A22), const Color(0xFFF0B24A)]},
      {'keys': ['guarantytrustbank', 'gtbank'], 'brand': 'GTBANK', 'mark': 'GT', 'colors': [const Color(0xFFE36C25), const Color(0xFF4B83B5)]},
      {'keys': ['zenithbank'], 'brand': 'ZENITH BANK', 'mark': 'ZENITH', 'colors': [const Color(0xFF7D1728), const Color(0xFFBA5360)]},
      {'keys': ['accessbank'], 'brand': 'ACCESS BANK', 'mark': 'ACCESS', 'colors': [const Color(0xFF8A1C3B), const Color(0xFFD65B79)]},
      {'keys': ['equitybank', 'equitygroup'], 'brand': 'EQUITY BANK', 'mark': 'EQUITY', 'colors': [const Color(0xFFB51F2B), const Color(0xFF4B8C69)]},
      {'keys': ['kcbgroup', 'kcbank'], 'brand': 'KCB BANK', 'mark': 'KCB', 'colors': [const Color(0xFF176B47), const Color(0xFF66A87C)]},
      {'keys': ['absa'], 'brand': 'ABSA', 'mark': 'ABSA', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['fnbbank', 'firstnationalbank'], 'brand': 'FNB', 'mark': 'FNB', 'colors': [const Color(0xFF087A50), const Color(0xFF64B18A)]},
      {'keys': ['attijariwafabank', 'attijariwafa'], 'brand': 'ATTIJARIWAFA BANK', 'mark': 'AWB', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['commercialinternationalbank', 'cibegypt'], 'brand': 'CIB', 'mark': 'CIB', 'colors': [const Color(0xFF174B85), const Color(0xFF6B9BC8)]},
      {'keys': ['bankcentralasia', 'bca'], 'brand': 'BANK CENTRAL ASIA', 'mark': 'BCA', 'colors': [const Color(0xFF07529B), const Color(0xFF4A91C8)]},
      {'keys': ['bankmandiri', 'mandiri'], 'brand': 'BANK MANDIRI', 'mark': 'MANDIRI', 'colors': [const Color(0xFF087B55), const Color(0xFF5BB38A)]},
      {'keys': ['bankrakyatindonesia', 'bri'], 'brand': 'BANK BRI', 'mark': 'BRI', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['bankofphilippineislands', 'bpi'], 'brand': 'BPI', 'mark': 'BPI', 'colors': [const Color(0xFF8A1D2D), const Color(0xFFD85C69)]},
      {'keys': ['bdobank', 'bdounibank'], 'brand': 'BDO', 'mark': 'BDO', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['vietcombank'], 'brand': 'VIETCOMBANK', 'mark': 'VCB', 'colors': [const Color(0xFF087A4B), const Color(0xFF63B487)]},
      {'keys': ['kbkookmin', 'kookminbank'], 'brand': 'KB KOOKMIN BANK', 'mark': 'KB', 'colors': [const Color(0xFF6B4A86), const Color(0xFFB28BC9)]},
      {'keys': ['shinhanbank', 'shinhan'], 'brand': 'SHINHAN BANK', 'mark': 'SHINHAN', 'colors': [const Color(0xFF1766A1), const Color(0xFF69A8D0)]},
      {'keys': ['ctbcbank', 'ctbc'], 'brand': 'CTBC BANK', 'mark': 'CTBC', 'colors': [const Color(0xFF087A4B), const Color(0xFF63B487)]},
      {'keys': ['ubs'], 'brand': 'UBS', 'mark': 'UBS', 'colors': [const Color(0xFF292D35), const Color(0xFF777E88)]},
      {'keys': ['intesasanpaolo', 'intesabank'], 'brand': 'INTESA SANPAOLO', 'mark': 'ISP', 'colors': [const Color(0xFF087B55), const Color(0xFF58B28C)]},
      {'keys': ['unicredit'], 'brand': 'UNICREDIT', 'mark': 'U', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['santander'], 'brand': 'SANTANDER', 'mark': 'SANTANDER', 'colors': [const Color(0xFFB51F2B), const Color(0xFFE46A72)]},
      {'keys': ['ingbank', 'inggroup'], 'brand': 'ING', 'mark': 'ING', 'colors': [const Color(0xFFE36C25), const Color(0xFFF0B24A)]},
      {'keys': ['nordea'], 'brand': 'NORDEA', 'mark': 'NORDEA', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
      {'keys': ['pkobankpolski', 'pkobp'], 'brand': 'PKO BANK POLSKI', 'mark': 'PKO', 'colors': [const Color(0xFF174B85), const Color(0xFF69A1CE)]},
    ];
    // Resolve the most specific bank alias first. Short aliases such as
    // "hbl", "ubl" and "abl" must never steal a match from a longer name.
    var bankSeed = 0;
    for (final unit in name.codeUnits) {
      bankSeed = (bankSeed * 31 + unit) & 0x7fffffff;
    }
    final matchingThemes = themes.where((theme) {
      final aliases = theme['keys'] as List<String>;
      return aliases.any((alias) => name == alias);
    }).toList();
    if (matchingThemes.isEmpty) {
      final candidates = <({Map<String, dynamic> theme, String alias})>[];
      for (final theme in themes) {
        for (final alias in theme['keys'] as List<String>) {
          if (alias.length >= 4 && name.contains(alias)) {
            candidates.add((theme: theme, alias: alias));
          }
        }
      }
      candidates.sort((a, b) => b.alias.length.compareTo(a.alias.length));
      if (candidates.isNotEmpty) matchingThemes.add(candidates.first.theme);
    }
    if (matchingThemes.isNotEmpty) {
      final selected = Map<String, dynamic>.from(matchingThemes.first);
      // Each bank gets a repeatable card-face pattern instead of one generic
      // diagonal background; official artwork remains separately verified.
      selected['pattern'] ??= bankSeed % 6;
      return selected;
    }
    // Global fallback: any bank name receives a stable, distinct card
    // treatment, even when its official card artwork is not curated yet.
    final normalizedName = bankName.trim();
    var seed = 0;
    for (final unit in normalizedName.toLowerCase().codeUnits) {
      seed = (seed * 31 + unit) & 0x7fffffff;
    }
    const fallbackPalettes = <List<Color>>[
      [Color(0xFF123B67), Color(0xFF2676A8)],
      [Color(0xFF174B3B), Color(0xFF4C9873)],
      [Color(0xFF4B285F), Color(0xFF8B5AA6)],
      [Color(0xFF71333A), Color(0xFFB65B61)],
      [Color(0xFF80531D), Color(0xFFC18B3D)],
      [Color(0xFF263746), Color(0xFF657D91)],
      [Color(0xFF155C63), Color(0xFF3B9B9A)],
      [Color(0xFF4B456E), Color(0xFF8580B0)],
    ];
    final fallbackMark = normalizedName.isEmpty
        ? 'BANK'
        : normalizedName.toUpperCase().split(RegExp(r'\\s+'))
            .where((part) => part.isNotEmpty).take(3)
            .map((part) => part[0]).join();
    return {
      'brand': normalizedName.isEmpty ? 'BANK' : normalizedName.toUpperCase(),
      'mark': fallbackMark,
      'colors': fallbackPalettes[seed % fallbackPalettes.length],
      'pattern': seed % 6,
      'isKnown': false,
    };
  }

  Widget _buildPremiumWalletCard({
    required Map<String, dynamic> wallet,
    required double balance,
    required String currency,
    required String walletType,
    required bool excluded,
  }) {
    final type = walletType.toLowerCase();
    final isDebit = type.contains('debit');
    final isCredit = type.contains('credit');
    final bankTheme = _bankCardTheme((wallet['name'] ?? '').toString());
    // Treat every bank/debit/credit/digital-card entry as institution-branded.
    // Unknown institutions use the deterministic name-based fallback theme;
    // known institutions use their curated brand palette.
    final isBank = type == 'bank' || type.contains('bank') ||
        type.contains('debit') || type.contains('credit') || type.contains('digital');
    final isCash = type == 'cash';
    final isDigital = type.contains('digital');
    final isInvestment = type.contains('investment');
    final colors = isDebit && !isBank
        ? const [Color(0xFF073B66), Color(0xFF087E9B)]
        : isCredit && !isBank
            ? const [Color(0xFF30205F), Color(0xFF8B3D83)]
            : isBank
                ? (bankTheme!['colors'] as List<Color>)
                : isCash
                    ? const [Color(0xFF8A5A16), Color(0xFFD69B36)]
                    : isDigital
                        ? const [Color(0xFF263B85), Color(0xFF4779D5)]
                        : isInvestment
                            ? const [Color(0xFF174B38), Color(0xFF68A65B)]
                            : const [Color(0xFF34445A), Color(0xFF71839A)];
    final iconCode = (wallet['icon_code'] as num?)?.toInt() ?? Icons.wallet_outlined.codePoint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(19),
        onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => TransactionsScreen(
            walletId: wallet['id'] as int,
            walletName: wallet['name'] as String,
          ),
        )),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            borderRadius: BorderRadius.circular(17),
            boxShadow: [
              BoxShadow(color: colors.first.withValues(alpha: 0.22),
                blurRadius: 9, offset: const Offset(0, 4)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Stack(
              children: [
                if (isBank) Positioned.fill(
                  child: IgnorePointer(child: CustomPaint(
                    painter: _BankCardPatternPainter(
                      pattern: (bankTheme?['pattern'] as int?) ?? 0,
                      design: (bankTheme?['design'] ?? '').toString(),
                      color: const Color(0xFFD9BD82),
                    ),
                  )),
                ),
                if (!isBank) Positioned(right: -23, top: -35,
                  child: Container(width: 125, height: 125,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 18)))),
                                if (!isBank) Positioned(right: 24, bottom: -57,
                  child: Container(width: 145, height: 145,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.055)))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (isBank)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                            ),
                            child: Text(bankTheme!['mark'] as String,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                          )
                        else
                          Icon(Icons.contactless_rounded, color: Colors.white.withValues(alpha: 0.9), size: 17),
                        if (isBank) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 25,
                            height: 18,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFE9D49A), Color(0xFFB89550)],
                              ),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 0.6),
                            ),
                            child: const Center(
                              child: Icon(Icons.memory_rounded, size: 14, color: Color(0xFF70572C)),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (isBank) ...[
                          Icon(Icons.contactless_rounded, color: Colors.white.withValues(alpha: 0.9), size: 17),
                          const SizedBox(width: 7),
                        ],
                        if (excluded) const Icon(Icons.visibility_off_outlined, color: Colors.white70, size: 14),
                        if (isDebit || isCredit) ...[
                          const SizedBox(width: 5),
                          SizedBox(width: 32, height: 20,
                            child: Stack(children: [
                              Positioned(left: 0, child: Container(width: 19, height: 19,
                                decoration: BoxDecoration(color: const Color(0xFFE53935).withValues(alpha: 0.95), shape: BoxShape.circle))),
                              Positioned(right: 0, child: Container(width: 21, height: 21,
                                decoration: BoxDecoration(color: const Color(0xFFFFB300).withValues(alpha: 0.95), shape: BoxShape.circle))),
                            ])),
                        ] else
                          Icon(IconData(iconCode, fontFamily: 'MaterialIcons'), color: Colors.white, size: 20),
                      ]),
                      const Spacer(),
                      Text(formatMoney(balance, currency), maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 15,
                          fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                      const SizedBox(height: 1),
                      Row(children: [
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(isBank ? (bankTheme!['brand'] as String) : (wallet['name'] ?? 'Wallet').toString().toUpperCase(),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 9,
                              fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          Text(walletType.toUpperCase(), maxLines: 1,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 7.5, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
                        ])),
                        if (isDebit || isCredit)
                          const Text('mastercard', style: TextStyle(color: Colors.white,
                            fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: -0.3))
                        else
                          Icon(isCash ? Icons.payments_outlined : isBank
                              ? Icons.account_balance_outlined
                              : isDigital ? Icons.phone_android_rounded
                              : isInvestment ? Icons.trending_up_rounded
                              : Icons.wallet_outlined,
                            color: Colors.white.withValues(alpha: 0.9), size: 19),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: GeneralPreferences.instance.personalizedHeaderTitle(context, Text(
          appText(context, 'My Wallets', 'میرے والٹس'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
        )),
        actions: [...buildMainSectionAppBarActions(context)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
                  child: Row(
                    children: [
                      Text(
                        appText(context, 'My Wallets', 'میرے والٹس'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface),
                      ),
                      const SizedBox(width: 7),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          foregroundColor: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () => openWalletForm(),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: Text(appText(context, 'Add Wallet', 'والٹ شامل کریں'),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 5),
                      const Expanded(child: SizedBox()),
                      Container(
                        width: 92,
                        height: 22,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            Expanded(
                              child: Material(
                                color: _usePremiumCards
                                    ? Colors.transparent
                                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                                child: InkWell(
                                  onTap: () => setState(() => _usePremiumCards = false),
                                  child: Center(
                                    child: Text(
                                      'Classic',
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: _usePremiumCards
                                            ? Theme.of(context).colorScheme.onSurface
                                            : Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 1,
                              color: Theme.of(context).colorScheme.outlineVariant,
                            ),
                            Expanded(
                              child: Material(
                                color: _usePremiumCards
                                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () => setState(() => _usePremiumCards = true),
                                  child: Center(
                                    child: Text(
                                      'Modern',
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: _usePremiumCards
                                            ? Theme.of(context).colorScheme.primary
                                            : Theme.of(context).colorScheme.onSurface,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 2),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          await Navigator.push(context, MaterialPageRoute(
                            builder: (_) => WalletManagementPage(
                              hideBalances: hideBalances,
                              numberFormat: numberFormat,
                            ),
                          ));
                          await loadWallets();
                        },
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.tune_rounded, size: 18),
                          const SizedBox(width: 2),
                          Text(appText(context, 'Manage', 'انتظام کریں')),
                        ]),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: wallets.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_balance_wallet_outlined,
                                  size: 58, color: Theme.of(context).colorScheme.primary),
                              SizedBox(height: 12),
                              Text(appText(context, 'No wallets added yet',
                                  'ابھی کوئی والٹ شامل نہیں کیا گیا'),
                                  style: TextStyle(color: Theme.of(context).hintColor)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: loadWallets,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 7, 16, 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 1.88,
                            ),
                            itemCount: wallets.length,
                            itemBuilder: (context, index) {
                      final wallet = wallets[index];
                      final balance = (wallet['balance'] as num).toDouble();
                      final currency = wallet['currency'] as String;
                      final iconCode = wallet['icon_code'] as int;
                      final rawWalletType = (wallet['type'] as String?) ?? 'Wallet';
                      final customWalletType = wallet['custom_type']?.toString().trim() ?? '';
                      final walletType = rawWalletType == 'Custom' && customWalletType.isNotEmpty
                          ? customWalletType
                          : rawWalletType;
                      final excluded = (wallet['exclude_total'] as int) == 1;

                      if (_usePremiumCards) {
                        return _buildPremiumWalletCard(
                          wallet: wallet,
                          balance: balance,
                          currency: currency,
                          walletType: walletType,
                          excluded: excluded,
                        );
                      }
                      return Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: const BorderSide(color: Color(0xFFE5ECE8)),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => TransactionsScreen(
                              walletId: wallet['id'] as int,
                              walletName: wallet['name'] as String,
                            ),
                          )),
                          child: Stack(
                          children: [
                            Positioned.fill(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  widthFactor: 1,
                                  heightFactor: 0.72,
                                  child: CustomPaint(
                                    painter: _WalletWavePainter(AppColors.primary),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 34, height: 34,
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(9),
                                        ),
                                        child: Icon(IconData(iconCode, fontFamily: 'MaterialIcons'),
                                            color: AppColors.primary, size: 20),
                                      ),
                                      SizedBox(width: 5),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(wallet['name'] as String,
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 11.5,
                                                fontWeight: FontWeight.w800, color: AppColors.text)),
                                            SizedBox(height: 2),
                                            Text(walletType, maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 10,
                                                fontWeight: FontWeight.w700, color: AppColors.primary)),
                                          ],
                                        ),
                                      ),
                                      if (excluded) Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          size: 19,
                                          color: AppColors.expense,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 47,
                                        child: Text(appText(context, 'BALANCE', 'بیلنس'), textAlign: TextAlign.left,
                                          style: TextStyle(fontSize: 9,
                                            fontWeight: FontWeight.w800, color: Colors.white)),
                                      ),
                                      Expanded(
                                        child: Text(formatMoney(balance, currency),
                                          maxLines: 1, textAlign: TextAlign.end,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 12,
                                            fontWeight: FontWeight.w900, color: Colors.white,
                                            letterSpacing: -0.2)),
                                      ),
                                      if (excluded) ...[
                                        SizedBox(width: 3),
                                        const Icon(Icons.visibility_off_outlined,
                                          size: 11, color: Colors.white),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                          ),
                        ),
                      );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

// ============================================================
// Wallet add ya edit karne ka form
// ============================================================

class WalletFormDialog extends StatefulWidget {
  final Map<String, dynamic>? wallet;

  const WalletFormDialog({
    super.key,
    this.wallet,
  });

  @override
  State<WalletFormDialog> createState() => _WalletFormDialogState();
}

class _WalletFormDialogState extends State<WalletFormDialog> {
  final formKey = GlobalKey<FormState>();

  late final TextEditingController nameController;
  late final TextEditingController customTypeController;
  late final TextEditingController openingController;
  late final TextEditingController currentController;
  late final TextEditingController numberController;

  late String selectedType;
  late String selectedCurrency;
  late int selectedIcon;
  late bool excludeTotal;

  bool saving = false;
  final GlobalKey _currencyPickerKey = GlobalKey();
  final GlobalKey _walletTypePickerKey = GlobalKey();

  bool get isEditing => widget.wallet != null;

  @override
  void initState() {
    super.initState();

    final wallet = widget.wallet;
        nameController = TextEditingController(
      text: wallet?['name'] as String? ?? '',
    );
    customTypeController = TextEditingController(
      text: wallet?['custom_type'] as String? ?? '',
    );
    openingController = TextEditingController(
      text: (wallet?['opening_balance'] ?? 0).toString(),
    );
    currentController = TextEditingController(
      text: (wallet?['balance'] ?? 0).toString(),
    );
    numberController = TextEditingController(
      text: wallet?['wallet_number'] as String? ?? '',
    );

    selectedType = wallet?['type'] as String? ?? 'Cash';
    selectedCurrency = wallet?['currency'] as String? ?? 'PKR';
    _loadBaseCurrencyAsDefault();

    if (!walletTypes.contains(selectedType)) selectedType = 'Other';
    if (!CurrencyCatalog.supported.contains(selectedCurrency) && !isEditing) {
      selectedCurrency = 'PKR';
    }

    selectedIcon =
        wallet?['icon_code'] as int? ?? walletIcons.first.codePoint;
    excludeTotal = (wallet?['exclude_total'] as int? ?? 0) == 1;
  }

  Future<void> _loadBaseCurrencyAsDefault() async {
    if (isEditing) return;
    try {
      final baseCurrency = await FinanceDB.instance.getBaseCurrency();
      if (!mounted || !CurrencyCatalog.supported.contains(baseCurrency)) return;
      setState(() => selectedCurrency = baseCurrency);
    } catch (_) {
      // Keep PKR as a safe default if preferences cannot be read.
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    customTypeController.dispose();
    openingController.dispose();
    currentController.dispose();
    numberController.dispose();
    super.dispose();
  }

  double readAmount(TextEditingController controller) {
    return double.tryParse(controller.text.trim()) ?? 0;
  }

  Future<void> saveWallet() async {
    if (!formKey.currentState!.validate()) return;

    setState(() => saving = true);

    try {
      if (isEditing) {
        await FinanceDB.instance.updateWallet(
          id: widget.wallet!['id'] as int,
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          requestedCurrentBalance: readAmount(currentController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      } else {
        await FinanceDB.instance.addWallet(
          name: nameController.text,
          type: selectedType,
          customType: selectedType == 'Custom'
              ? customTypeController.text.trim()
              : null,
          currency: selectedCurrency,
          openingBalance: readAmount(openingController),
          walletNumber: numberController.text.trim().isEmpty
              ? null
              : numberController.text.trim(),
          iconCode: selectedIcon,
          excludeTotal: excludeTotal,
        );
      }

      if (await GeneralPreferences.instance.hapticFeedback) {
        await HapticFeedback.selectionClick();
      }
      if (!mounted) return;
      await SoundSettingsService.instance.play(isEditing ? 'update' : 'save');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
      setState(() => saving = false);
    }
  }

  static const Map<String,String> _walletCurrencyFlags = {'PKR':'🇵🇰','USD':'🇺🇸','GBP':'🇬🇧','EUR':'🇪🇺','AED':'🇦🇪','SAR':'🇸🇦','INR':'🇮🇳','CAD':'🇨🇦','AUD':'🇦🇺','JPY':'🇯🇵','CNY':'🇨🇳','CHF':'🇨🇭','SGD':'🇸🇬','NZD':'🇳🇿','KWD':'🇰🇼','QAR':'🇶🇦','BHD':'🇧🇭','OMR':'🇴🇲','MYR':'🇲🇾','TRY':'🇹🇷','ZAR':'🇿🇦','HKD':'🇭🇰','IDR':'🇮🇩','KRW':'🇰🇷','THB':'🇹🇭'};
  static const Map<String,String> _walletCurrencyNames = {'PKR':'Pakistani Rupee','USD':'US Dollar','GBP':'British Pound','EUR':'Euro','AED':'UAE Dirham','SAR':'Saudi Riyal','INR':'Indian Rupee','CAD':'Canadian Dollar','AUD':'Australian Dollar','JPY':'Japanese Yen','CNY':'Chinese Yuan','CHF':'Swiss Franc','SGD':'Singapore Dollar','NZD':'New Zealand Dollar','KWD':'Kuwaiti Dinar','QAR':'Qatari Riyal','BHD':'Bahraini Dinar','OMR':'Omani Rial','MYR':'Malaysian Ringgit','TRY':'Turkish Lira','ZAR':'South African Rand','HKD':'Hong Kong Dollar','IDR':'Indonesian Rupiah','KRW':'South Korean Won','THB':'Thai Baht'};

  static const Map<String, IconData> _walletTypeIcons = {
    'Cash': Icons.payments_outlined,
    'Bank': Icons.account_balance_outlined,
    'Credit Card': Icons.credit_card_outlined,
    'Debit Card': Icons.credit_card_rounded,
    'Digital Wallet': Icons.account_balance_wallet_outlined,
    'Investment': Icons.trending_up_rounded,
    'Other': Icons.category_outlined,
    'Custom': Icons.tune_rounded,
  };

  Offset _pickerAnchorCenter(GlobalKey key) {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final topLeft = renderObject.localToGlobal(Offset.zero);
      return Offset(topLeft.dx + renderObject.size.width / 2, topLeft.dy);
    }
    final size = MediaQuery.sizeOf(context);
    return Offset(size.width / 2, size.height * .65);
  }

  Alignment _dialogAlignmentCenteredOnAnchor(Offset anchor, Size screen) {
    final centerX = anchor.dx.clamp(12.0, screen.width - 12.0);
    final centerY = anchor.dy.clamp(12.0, screen.height - 12.0);
    return Alignment(
      (centerX / screen.width) * 2 - 1,
      (centerY / screen.height) * 2 - 1,
    );
  }

  Alignment _dialogAlignmentAbove(Offset anchor, Size screen, double height) {
    final centerX = anchor.dx.clamp(12.0, screen.width - 12.0);
    final top = (anchor.dy - height - 8).clamp(8.0, screen.height - height - 8);
    final centerY = top + height / 2;
    return Alignment(
      (centerX / screen.width) * 2 - 1,
      (centerY / screen.height) * 2 - 1,
    );
  }

  Future<void> _showWalletTypePicker() async {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final anchor = _pickerAnchorCenter(_walletTypePickerKey);
    const popupHeight = 370.0;
    final popupWidth = screen.width < 190 ? screen.width - 20 : 174.0;
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        insetPadding: EdgeInsets.zero,
        alignment: _dialogAlignmentCenteredOnAnchor(anchor, screen),
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        constraints: BoxConstraints.tightFor(width: popupWidth, height: popupHeight),
        child: SizedBox(
          width: popupWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: walletTypes.map((type) {
                final selected = type == selectedType;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Material(
                    color: selected
                        ? theme.colorScheme.primaryContainer.withOpacity(.65)
                        : theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(11),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(11),
                      onTap: () => Navigator.pop(dialogContext, type),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                        child: Row(children: [
                          Icon(_walletTypeIcons[type] ?? Icons.wallet_outlined,
                            size: 19, color: selected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 7),
                          Expanded(child: Text(type, maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                          if (selected) Icon(Icons.check_circle_rounded,
                            size: 16, color: theme.colorScheme.primary),
                        ]),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => selectedType = picked);
    }
  }

  Future<void> _showWalletCurrencyPicker() async {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final anchor = _pickerAnchorCenter(_currencyPickerKey);
    final availableAbove = (anchor.dy - 12).clamp(180.0, screen.height * .82);
    final popupHeight = availableAbove.toDouble();
    final popupWidth = (screen.width - 32).clamp(210.0, 232.0).toDouble();
    final picked = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        var query = '';
        return StatefulBuilder(builder: (context, setDialogState) {
          final currencies = CurrencyCatalog.supported.toList()..sort();
          final filtered = currencies.where((code) {
            final name = _walletCurrencyNames[code] ?? code;
            final q = query.trim().toLowerCase();
            return q.isEmpty || code.toLowerCase().contains(q) || name.toLowerCase().contains(q);
          }).toList();
          return Dialog(
            insetPadding: EdgeInsets.zero,
            alignment: _dialogAlignmentAbove(anchor, screen, popupHeight),
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            constraints: BoxConstraints.tightFor(width: popupWidth, height: popupHeight),
            child: SizedBox(
              width: popupWidth,
              height: popupHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Container(width: 34, height: 4, decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ))),
                  const SizedBox(height: 14),
                  Text('Choose currency', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Search by name or code', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setDialogState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      prefixIconConstraints: const BoxConstraints(minWidth: 36),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest,
                      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(13),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final code = filtered[index];
                      final selected = code == selectedCurrency;
                      return Material(
                        color: selected
                            ? theme.colorScheme.primaryContainer.withOpacity(.65)
                            : theme.colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.pop(dialogContext, code),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(children: [
                              Text(_walletCurrencyFlags[code] ?? '🌐',
                                style: const TextStyle(fontSize: 21)),
                              const SizedBox(width: 7),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(code, maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                                  Text(_walletCurrencyNames[code] ?? code,
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                                  ),
                                ],
                              )),
                              if (selected) Icon(Icons.check_circle_rounded,
                                size: 17, color: theme.colorScheme.primary),
                            ]),
                          ),
                        ),
                      );
                    },
                  )),
                ]),
              ),
            ),
          );
        });
      },
    );
    if (picked != null && mounted) setState(() => selectedCurrency = picked);
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon == null ? null : Icon(icon, size: 19),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E9E5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
      isDense: true,
    );
  }

  Widget _buildIconPicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 16 icons ko 8 columns mein rakh kar 2 rows banata hai.
        const spacing = 6.0;
        final itemWidth = (constraints.maxWidth - spacing * 7) / 8;

        return Wrap(
          spacing: spacing,
          runSpacing: 6,
          children: walletIcons.map((icon) {
            final selected = selectedIcon == icon.codePoint;

            return InkWell(
              onTap: () => setState(() => selectedIcon = icon.codePoint),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: itemWidth,
                height: 37,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withValues(alpha: 0.12)
                      : const Color(0xFFF4F7F5),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE8EEEA),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? AppColors.primary : AppColors.muted,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardIsOpen = keyboardHeight > 0;
    final maxSheetHeight = keyboardIsOpen
        ? (screenHeight - keyboardHeight).clamp(0.0, screenHeight) * 0.95
        : screenHeight * 0.72;

    // Keyboard khulne par bottom sheet uski jagah ke mutabiq narmi se upar jati hai.
    // Keyboard band hone par sheet apni pehli jagah par wapas aa jati hai.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              child: Form(
                key: formKey,
                // Sheet ko scroll karne ke bajaye keyboard khulne par upar le jana.
                child: SingleChildScrollView(
                  primary: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sheet ko kheenchne ke liye chhota handle.
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD9E0DC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isEditing ? 'Edit Wallet' : 'Add Wallet',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close_rounded),
                            color: AppColors.muted,
                          ),
                        ],
                      ),
                      SizedBox(height: 10),

                      // Pehli row mein wallet ka naam aur qisam.
                      Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: TextFormField(
                              controller: nameController,
                              decoration: _fieldDecoration(
                                'Wallet Name',
                                icon: Icons.account_balance_wallet_outlined,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Name required';
                                }
                                return null;
                              },
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              key: _walletTypePickerKey,
                              height: 56,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: saving ? null : _showWalletTypePicker,
                                child: InputDecorator(
                                  decoration: _fieldDecoration('Wallet Type'),
                                  child: Row(children: [
                                    Icon(_walletTypeIcons[selectedType] ?? Icons.wallet_outlined,
                                      size: 19, color: AppColors.primary),
                                    const SizedBox(width: 7),
                                    Expanded(child: Text(selectedType,
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13))),
                                    const Icon(Icons.arrow_drop_down_rounded, size: 21),
                                  ]),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (selectedType == 'Custom') ...[
                        SizedBox(height: 9),
                        TextFormField(
                          controller: customTypeController,
                          decoration: _fieldDecoration('Custom Wallet Type'),
                          validator: (value) {
                            if (selectedType == 'Custom' &&
                                (value == null || value.trim().isEmpty)) {
                              return 'Custom type required';
                            }
                            return null;
                          },
                        ),
                      ],

                      SizedBox(height: 8),
                      Text(appText(context, "Wallet Icon", "Wallet Icon"),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      SizedBox(height: 5),
                      _buildIconPicker(),

                      SizedBox(height: 8),

                      // Currency aur amount aik hi row mein.
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: SizedBox(
                              key: _currencyPickerKey,
                              height: 56,
                              child: Material(
                              color: Theme.of(context).colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: saving ? null : _showWalletCurrencyPicker,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  child: Row(children: [
                                    Text(_walletCurrencyFlags[selectedCurrency] ?? '🌐',
                                      style: const TextStyle(fontSize: 23)),
                                    const SizedBox(width: 8),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Text(selectedCurrency, maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                                      Text(_walletCurrencyNames[selectedCurrency] ?? selectedCurrency,
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                    ])),
                                    const Icon(Icons.unfold_more_rounded, size: 18),
                                  ]),
                                ),
                              ),
                            ),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: isEditing
                                  ? currentController
                                  : openingController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                                signed: true,
                              ),
                              decoration: _fieldDecoration(
                                isEditing
                                    ? 'Current Balance'
                                    : 'Opening Balance',
                              ),
                              validator: (value) {
                                if (value == null ||
                                    double.tryParse(value.trim()) == null) {
                                  return 'Enter valid amount';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 7),
                      TextFormField(
                        controller: numberController,
                        decoration: _fieldDecoration(
                          'Wallet Number (Optional)',
                          icon: Icons.numbers_outlined,
                        ),
                      ),

                      SizedBox(height: 3),
                      // Label aur standard toggle aik hi seedhi line mein.
                      Row(
                        children: [
                          Expanded(
                            child: Text(appText(context, "Exclude from Total Balance", "Exclude from Total Balance"),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                          Switch.adaptive(
                            value: excludeTotal,
                            activeTrackColor: AppColors.primary,
                            onChanged: (value) {
                              setState(() => excludeTotal = value);
                            },
                          ),
                        ],
                      ),

                      SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                foregroundColor: AppColors.text,
                                side: const BorderSide(
                                  color: Color(0xFFDDE5E0),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: Text(appText(context, 'Cancel', 'منسوخ کریں')), 
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: saving ? null : saveWallet,
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: saving
                                  ? SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(appText(context, "Save Wallet", "Save Wallet"),
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================


// ============================================================
// Wallet management: ordering, archive/restore and delete
// ============================================================
class WalletManagementPage extends StatefulWidget {
  final bool hideBalances;
  final String numberFormat;
  const WalletManagementPage({super.key, required this.hideBalances, required this.numberFormat});
  @override
  State<WalletManagementPage> createState() => _WalletManagementPageState();
}

class _WalletManagementPageState extends State<WalletManagementPage> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _active = [];
  List<Map<String, dynamic>> _hidden = [];
  bool _loading = true;
  String? _loadError;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    AppRefreshController.revision.addListener(_onAppDataChanged);
    _load();
  }

  void _onAppDataChanged() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    AppRefreshController.revision.removeListener(_onAppDataChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _saveIds(String key, List<int> ids) async {
    await FinanceDB.instance.db.insert('app_settings',
      {'setting_key': key, 'setting_value': jsonEncode(ids)},
      conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _loadError = null; });
    try {
      final db = FinanceDB.instance.db;
      final all = List<Map<String, dynamic>>.from(await db.query('wallets'));
      final rows = await db.query('app_settings',
        where: 'setting_key IN (?, ?)',
        whereArgs: ['hidden_wallet_ids', 'wallet_display_order']);
      final values = {for (final r in rows) r['setting_key'].toString(): r['setting_value']?.toString() ?? ''};
      List<int> hidden = [], order = [];
      try { hidden = (jsonDecode(values['hidden_wallet_ids'] ?? '[]') as List).map((e)=>(e as num).toInt()).toList(); } catch (_) {}
      try { order = (jsonDecode(values['wallet_display_order'] ?? '[]') as List).map((e)=>(e as num).toInt()).toList(); } catch (_) {}
      all.sort((a,b) {
        final ai=order.indexOf((a['id'] as num).toInt());
        final bi=order.indexOf((b['id'] as num).toInt());
        if(ai<0&&bi<0)return 0; if(ai<0)return 1; if(bi<0)return -1;
        return ai.compareTo(bi);
      });
      if (!mounted) return;
      setState(() {
        _active = all.where((w)=>!hidden.contains((w['id'] as num).toInt())).toList();
        _hidden = all.where((w)=>hidden.contains((w['id'] as num).toInt())).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  String _money(Map<String,dynamic> w) {
    if (widget.hideBalances) return '${w['currency']} ******';
    final locale = widget.numberFormat == '1.234,56' ? 'de_DE' : 'en_US';
    return "${w['currency']} ${NumberFormat('#,##0.00', locale).format((w['balance'] as num).toDouble())}";
  }

  Future<void> _setWalletHidden(Map<String,dynamic> wallet, bool hidden) async {
    final id=(wallet['id'] as num).toInt();
    final ids=_hidden.map((w)=>(w['id'] as num).toInt()).toList();
    if (hidden) { if(!ids.contains(id)) ids.add(id); } else { ids.remove(id); }
    await _saveIds('hidden_wallet_ids', ids);
    await _load();
  }

  Future<void> _edit(Map<String, dynamic> wallet) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WalletFormDialog(wallet: wallet),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Map<String,dynamic> wallet) async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title: Text(appText(context,'Delete Wallet?','والٹ حذف کریں؟')),
      content: Text('Delete "${wallet['name']}"? This cannot be undone here.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:Text(appText(context,'Cancel','منسوخ کریں'))),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:Text(appText(context,'Delete','حذف کریں')))]));
    if(yes!=true)return;
    try { await FinanceDB.instance.deleteWallet((wallet['id'] as num).toInt()); await _load(); }
    catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(e.toString().replaceFirst('Exception: ','')))); }
  }

  Widget _walletTile(Map<String,dynamic> w,{required bool hidden}) {
    final icon=IconData((w['icon_code'] as num).toInt(),fontFamily:'MaterialIcons');
    return Card(margin:const EdgeInsets.symmetric(horizontal:12,vertical:2),child:ListTile(
      dense: true,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
      minVerticalPadding: 2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      leading: Icon(icon,color:Theme.of(context).colorScheme.primary,size:21),
      title: Text(w['name']?.toString() ?? 'Wallet',style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
      subtitle: Text(_money(w),style: const TextStyle(fontSize:11)),
      trailing: Row(mainAxisSize:MainAxisSize.min,children:[
        IconButton(
          tooltip: 'Edit Wallet',
          visualDensity: VisualDensity.compact,
          onPressed: () => _edit(w),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          tooltip: 'Delete Wallet',
          visualDensity: VisualDensity.compact,
          onPressed: () => _delete(w),
          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        ),
        IconButton(
          tooltip: hidden ? 'Unhide Wallet' : 'Hide Wallet',
          visualDensity: VisualDensity.compact,
          onPressed: () => _setWalletHidden(w, !hidden),
          icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
      ]),
    ));
  }

  Widget _activeList() {
    if (_active.isEmpty) return Center(child: Text(appText(context,'No active wallets','کوئی فعال والٹ موجود نہیں')));
    return ReorderableListView.builder(
      padding: const EdgeInsets.only(top:8,bottom:24),
      itemCount: _active.length,
      onReorder: (oldIndex,newIndex) async {
        if(newIndex>oldIndex)newIndex--;
        if(oldIndex<0 || oldIndex>=_active.length)return;
        final item=_active.removeAt(oldIndex);
        _active.insert(newIndex.clamp(0,_active.length).toInt(),item);
        setState((){});
        await _saveIds('wallet_display_order',
          _active.map((w)=>(w['id'] as num).toInt()).toList() +
          _hidden.map((w)=>(w['id'] as num).toInt()).toList());
      },
      itemBuilder: (context,index) {
        final w=_active[index];
        return Container(key:ValueKey('wallet_${w['id']}'),child:Row(children:[
          Padding(padding:const EdgeInsets.only(left:8),child:ReorderableDragStartListener(index:index,child:Icon(Icons.reorder_rounded,color:Theme.of(context).hintColor))),
          Expanded(child:_walletTile(w,hidden:false)),
        ]));
      },
    );
  }

  Widget _hiddenList() {
    if (_hidden.isEmpty) return Center(child: Text(appText(context,'No hidden wallets','کوئی پوشیدہ والٹ موجود نہیں')));
    return ListView(padding:const EdgeInsets.only(top:8,bottom:24),
      children:_hidden.map((w)=>_walletTile(w,hidden:true)).toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor:Theme.of(context).scaffoldBackgroundColor,
    appBar:AppBar(
      title:Text(appText(context,'Manage Wallets','والٹس کا انتظام')),
      backgroundColor:Colors.white,
      foregroundColor:Theme.of(context).colorScheme.onSurface,
      bottom:TabBar(
        controller:_tabs,
        labelColor:Theme.of(context).colorScheme.primary,
        unselectedLabelColor:Theme.of(context).hintColor,
        indicatorColor:Theme.of(context).colorScheme.primary,
        tabs:[
          Tab(text:'Active Wallets (${_active.length})'),
          Tab(text:'Hidden Wallets (${_hidden.length})'),
        ],
      ),
    ),
    body:_loading
      ? const Center(child:CircularProgressIndicator())
      : _loadError != null
        ? Center(child:Padding(padding:const EdgeInsets.all(20),child:Column(
            mainAxisSize:MainAxisSize.min,children:[
              Text('Wallets could not be loaded: $_loadError',textAlign:TextAlign.center),
              const SizedBox(height:12),FilledButton(onPressed:_load,child:const Text('Retry')),
            ])))
        : TabBarView(controller:_tabs,children:[_activeList(),_hiddenList()]),
  );
}