import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/modules/finance/models/assets_model.dart';
import 'package:my_finance/modules/finance/models/loans_model.dart';
import 'package:my_finance/modules/finance/services/assets_service.dart';
import 'package:my_finance/modules/finance/services/loans_service.dart';

const _bg = Color(0xFF101B2D), _card = Color(0xFF18263B), _card2 = Color(0xFF203149);
const _line = Color(0xFF2B3D54), _muted = Color(0xFF9AABC0), _white = Color(0xFFF4F7FB);
const _teal = Color(0xFF36C6B0), _blue = Color(0xFF65A8FF), _rose = Color(0xFFFF7D91);

/// Asset values aur un se mutaliq financial progress ka graph dikhata hai.
class AssetGraphScreen extends StatefulWidget {
  final bool hideBalances;
  const AssetGraphScreen({super.key, this.hideBalances = false});
  @override
  State<AssetGraphScreen> createState() => _AssetGraphScreenState();
}
class _AssetGraphScreenState extends State<AssetGraphScreen> {
  late final Future<List<AssetsModel>> _future = AssetsService().getAssets(includeSold: true);
  @override
  Widget build(BuildContext context) => FutureBuilder<List<AssetsModel>>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) return const _LoadingPage(title: 'Assets Analytics');
      if (s.hasError) return _ErrorPage(title: 'Assets Analytics', message: s.error.toString());
      final data = (s.data ?? const <AssetsModel>[]).map((a) => _Entry(
        name: a.name, currency: a.currency, amount: a.isSold ? (a.salePrice ?? 0) : a.currentValue,
        base: a.purchasePrice, status: a.isSold ? 'Sold' : 'Active', type: a.category,
      )).toList();
      return _Dashboard(title: 'Assets Analytics', subtitle: 'Portfolio overview and asset performance',
        icon: Icons.account_balance_rounded, entries: data, hide: widget.hideBalances, assets: true);
    },
  );
}

class LoanGraphScreen extends StatefulWidget {
  final bool hideBalances;
  const LoanGraphScreen({super.key, this.hideBalances = false});
  @override
  State<LoanGraphScreen> createState() => _LoanGraphScreenState();
}
class _LoanGraphScreenState extends State<LoanGraphScreen> {
  late final Future<List<LoansModel>> _future = LoansService.getLoans();
  @override
  Widget build(BuildContext context) => FutureBuilder<List<LoansModel>>(
    future: _future,
    builder: (context, s) {
      if (s.connectionState != ConnectionState.done) return const _LoadingPage(title: 'Loans Analytics');
      if (s.hasError) return _ErrorPage(title: 'Loans Analytics', message: s.error.toString());
      final data = (s.data ?? const <LoansModel>[]).map((l) => _Entry(
        name: 'Loan #${l.id ?? '-'}', currency: l.currency, amount: l.remainingAmount, base: l.amount,
        status: l.isOverdue ? 'Overdue' : (l.isPaid ? 'Paid' : 'Active'),
        type: l.loanType == 'given' ? 'Receivable' : 'Payable',
      )).toList();
      return _Dashboard(title: 'Loans Analytics', subtitle: 'Outstanding balances and repayment position',
        icon: Icons.account_balance_wallet_rounded, entries: data, hide: widget.hideBalances, assets: false);
    },
  );
}

class _Entry {
  final String name, currency, status, type;
  final double amount, base;
  const _Entry({required this.name, required this.currency, required this.amount,
    required this.base, required this.status, required this.type});
}

class _Dashboard extends StatefulWidget {
  final String title, subtitle;
  final IconData icon;
  final List<_Entry> entries;
  final bool hide, assets;
  const _Dashboard({required this.title, required this.subtitle, required this.icon,
    required this.entries, required this.hide, required this.assets});
  @override
  State<_Dashboard> createState() => _DashboardState();
}
class _DashboardState extends State<_Dashboard> {
  String filter = 'All';
  bool compareBase = false;
  String money(double n) => widget.hide ? '••••••' : NumberFormat('#,##0.##').format(n);
  double value(_Entry e) => compareBase ? e.base : e.amount;
  double sum(Iterable<_Entry> es, double Function(_Entry) f) => es.fold(0.0, (v, e) => v + f(e));
  @override
  Widget build(BuildContext context) {
    final all = widget.entries;
    final active = all.where((e) => e.status == 'Active').length;
    final closed = all.where((e) => e.status == 'Sold' || e.status == 'Paid').length;
    final overdue = all.where((e) => e.status == 'Overdue').length;
    final visible = all.where((e) => filter == 'All' || e.status == filter || e.type == filter).toList();
    final currencies = visible.map((e) => e.currency.toUpperCase()).toSet().toList()..sort();
    final currencySet = all.map((e) => e.currency.toUpperCase()).toSet();
    final heroValue = widget.hide ? '••••••' : (currencySet.length == 1 ? money(sum(all, (e) => e.amount)) : 'Multiple currencies');
    final labels = widget.assets ? ['All', 'Active', 'Sold'] : ['All', 'Receivable', 'Payable', 'Active', 'Overdue', 'Paid'];
    final metric = compareBase ? (widget.assets ? 'Purchase value' : 'Original amount')
      : (widget.assets ? 'Current / sale value' : 'Outstanding');
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(backgroundColor: _bg, foregroundColor: _white, elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
      body: all.isEmpty ? const _Empty() : ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _Hero(icon: widget.icon, subtitle: widget.subtitle,
            label: widget.assets ? 'PORTFOLIO VALUE' : 'TOTAL OUTSTANDING',
            value: heroValue, count: all.length,
            currencyCount: currencySet.length),
          const SizedBox(height: 13),
          Row(children: [
            Expanded(child: _Kpi(label: 'Active', value: '$active', color: _teal, icon: Icons.radio_button_checked_rounded)),
            const SizedBox(width: 8),
            Expanded(child: _Kpi(label: widget.assets ? 'Sold' : 'Paid', value: '$closed', color: _blue, icon: Icons.check_circle_outline_rounded)),
            if (!widget.assets) ...[
              const SizedBox(width: 8),
              Expanded(child: _Kpi(label: 'Overdue', value: '$overdue', color: _rose, icon: Icons.warning_amber_rounded)),
            ],
          ]),
          const SizedBox(height: 20),
          const _Heading(title: 'Analytics overview', subtitle: 'Status distribution across all records'),
          const SizedBox(height: 10),
          _StatusCard(active: active, closed: closed, overdue: overdue, total: all.length, assets: widget.assets),
          const SizedBox(height: 20),
          const _Heading(title: 'Currency analysis', subtitle: 'Currencies are never combined or converted'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(17), border: Border.all(color: _line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('FILTER RECORDS', style: TextStyle(color: _muted, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for (final f in labels) ...[
                  ChoiceChip(label: Text(f), selected: filter == f, onSelected: (_) => setState(() => filter = f),
                    showCheckmark: false, selectedColor: _teal,
                    backgroundColor: _card2, side: BorderSide(color: filter == f ? _teal : _line),
                    labelStyle: TextStyle(color: filter == f ? _bg : _muted, fontSize: 10, fontWeight: FontWeight.w800),
                    visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
                  const SizedBox(width: 5),
                ],
              ])),
              const SizedBox(height: 10),
              Container(height: 1, color: _line),
              const SizedBox(height: 9),
              Row(children: [
                const Expanded(child: Text('Compare values', style: TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700))),
                _Toggle(label: widget.assets ? 'Current / Sale' : 'Outstanding', selected: !compareBase,
                  onTap: () => setState(() => compareBase = false)),
                const SizedBox(width: 5),
                _Toggle(label: widget.assets ? 'Purchase' : 'Original', selected: compareBase,
                  onTap: () => setState(() => compareBase = true)),
              ]),
            ]),
          ),
          const SizedBox(height: 11),
          if (visible.isEmpty) const _NoMatches()
          else for (final c in currencies)
            _CurrencyCard(currency: c, entries: visible.where((e) => e.currency.toUpperCase() == c).toList(),
              value: value, metric: metric, money: money, assets: widget.assets),
          const SizedBox(height: 5),
          Text('${visible.length} records • ${currencies.length} currencies',
            textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final IconData icon;
  final String subtitle, label, value;
  final int count, currencyCount;
  const _Hero({required this.icon, required this.subtitle, required this.label,
    required this.value, required this.count, required this.currencyCount});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF203B50), Color(0xFF1A3044), Color(0xFF25334A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFF3A566B)),
      boxShadow: const [BoxShadow(color: Color(0x33101B2D), blurRadius: 22, offset: Offset(0, 9))],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: _teal.withValues(alpha: .15), borderRadius: BorderRadius.circular(13)),
          child: Icon(icon, color: _teal, size: 22)),
        const SizedBox(width: 11),
        Expanded(child: Text(subtitle, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600))),
        const Icon(Icons.insights_rounded, color: _teal, size: 23),
      ]),
      const SizedBox(height: 21),
      Text(label, style: const TextStyle(color: _muted, fontSize: 10, letterSpacing: 1.15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _white, fontSize: 29, fontWeight: FontWeight.w900, letterSpacing: -.5)),
      const SizedBox(height: 16),
      Container(height: 1, color: Colors.white.withValues(alpha: .10)),
      const SizedBox(height: 12),
      Row(children: [
        _HeroMeta(icon: Icons.layers_outlined, value: '$count', label: 'Records'),
        const SizedBox(width: 22),
        _HeroMeta(icon: Icons.currency_exchange_rounded, value: '$currencyCount', label: 'Currencies'),
      ]),
    ]),
  );
}
class _HeroMeta extends StatelessWidget {
  final IconData icon;
  final String value, label;
  const _HeroMeta({required this.icon, required this.value, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: _teal), const SizedBox(width: 6),
    Text(value, style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w800)),
    const SizedBox(width: 4), Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
  ]);
}
class _Kpi extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _Kpi({required this.label, required this.value, required this.color, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: color, size: 17), const SizedBox(height: 9),
      Text(value, style: const TextStyle(color: _white, fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 2), Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );
}
class _Heading extends StatelessWidget {
  final String title, subtitle;
  const _Heading({required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w900)),
    const SizedBox(height: 3), Text(subtitle, style: const TextStyle(color: _muted, fontSize: 10)),
  ]);
}
class _StatusCard extends StatelessWidget {
  final int active, closed, overdue, total;
  final bool assets;
  const _StatusCard({required this.active, required this.closed, required this.overdue, required this.total, required this.assets});
  @override
  Widget build(BuildContext context) {
    final vals = assets ? [active, closed] : [active, closed, overdue];
    final cols = assets ? [_teal, _blue] : [_teal, _blue, _rose];
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(19), border: Border.all(color: _line)),
      child: Row(children: [
        SizedBox(width: 110, height: 110, child: CustomPaint(painter: _RingPainter(values: vals.map((v) => v.toDouble()).toList(), colors: cols),
          child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$total', style: const TextStyle(color: _white, fontSize: 24, fontWeight: FontWeight.w900)),
            const Text('RECORDS', style: TextStyle(color: _muted, fontSize: 8, letterSpacing: .8)),
          ])))),
        const SizedBox(width: 16),
        Expanded(child: Column(children: [
          _StatusLine(color: _teal, label: 'Active', count: active, total: total),
          const SizedBox(height: 12),
          _StatusLine(color: _blue, label: assets ? 'Sold' : 'Paid', count: closed, total: total),
          if (!assets) ...[const SizedBox(height: 12), _StatusLine(color: _rose, label: 'Overdue', count: overdue, total: total)],
        ])),
      ]),
    );
  }
}
class _StatusLine extends StatelessWidget {
  final Color color;
  final String label;
  final int count, total;
  const _StatusLine({required this.color, required this.label, required this.count, required this.total});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8), Expanded(child: Text(label, style: const TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600))),
    Text('$count', style: const TextStyle(color: _white, fontSize: 12, fontWeight: FontWeight.w900)),
    const SizedBox(width: 6), Text(total == 0 ? '0%' : '${(count * 100 / total).round()}%',
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
  ]);
}
class _Toggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Toggle({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(9),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(color: selected ? _teal.withValues(alpha: .16) : _card2,
        borderRadius: BorderRadius.circular(9), border: Border.all(color: selected ? _teal : _line)),
      child: Text(label, style: TextStyle(color: selected ? _teal : _muted, fontSize: 9, fontWeight: FontWeight.w800))));
}
class _CurrencyCard extends StatelessWidget {
  final String currency, metric;
  final List<_Entry> entries;
  final double Function(_Entry) value;
  final String Function(double) money;
  final bool assets;
  const _CurrencyCard({required this.currency, required this.entries, required this.value,
    required this.metric, required this.money, required this.assets});
  @override
  Widget build(BuildContext context) {
    final sorted = [...entries]..sort((a, b) => value(b).compareTo(value(a)));
    final total = sorted.fold<double>(0, (s, e) => s + value(e));
    final maxValue = sorted.fold<double>(0, (m, e) => value(e) > m ? value(e) : m);
    return Container(
      margin: const EdgeInsets.only(bottom: 11), padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(19), border: Border.all(color: _line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: _teal.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
            child: Center(child: Text(currency, style: const TextStyle(color: _teal, fontSize: 9, fontWeight: FontWeight.w900)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$currency portfolio', style: const TextStyle(color: _white, fontSize: 13, fontWeight: FontWeight.w900)),
            Text('${entries.length} records • highest value first', style: const TextStyle(color: _muted, fontSize: 9)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(total), style: const TextStyle(color: _teal, fontSize: 15, fontWeight: FontWeight.w900)),
            Text(metric, style: const TextStyle(color: _muted, fontSize: 9)),
          ]),
        ]),
        const SizedBox(height: 15),
        for (var i = 0; i < sorted.length; i++) ...[
          _BarRow(entry: sorted[i], rank: i + 1, value: value(sorted[i]), maxValue: maxValue,
            color: sorted[i].status == 'Overdue' ? _rose :
              (sorted[i].status == 'Sold' || sorted[i].status == 'Paid' ? _blue : (assets ? _teal : _blue)),
            money: money),
          if (i != sorted.length - 1) const SizedBox(height: 15),
        ],
      ]),
    );
  }
}
class _BarRow extends StatelessWidget {
  final _Entry entry;
  final int rank;
  final double value, maxValue;
  final Color color;
  final String Function(double) money;
  const _BarRow({required this.entry, required this.rank, required this.value, required this.maxValue,
    required this.color, required this.money});
  @override
  Widget build(BuildContext context) {
    final ratio = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0).toDouble();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 19, height: 19, alignment: Alignment.center, decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(6)),
          child: Text('$rank', style: const TextStyle(color: _muted, fontSize: 9, fontWeight: FontWeight.w800))),
        const SizedBox(width: 7),
        Expanded(child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _white, fontSize: 10, fontWeight: FontWeight.w700))),
        Text(money(value), style: const TextStyle(color: _white, fontSize: 10, fontWeight: FontWeight.w900)),
      ]),
      const SizedBox(height: 7),
      ClipRRect(borderRadius: BorderRadius.circular(20), child: Stack(children: [
        Container(height: 7, color: _card2),
        FractionallySizedBox(widthFactor: ratio, child: Container(height: 7,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)))),
      ])),
      const SizedBox(height: 5),
      Row(children: [
        Expanded(child: Text(entry.type, style: const TextStyle(color: _muted, fontSize: 9))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
          child: Text(entry.status, style: TextStyle(color: color, fontSize: 8, fontWeight: FontWeight.w900))),
      ]),
    ]);
  }
}
class _RingPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _RingPainter({required this.values, required this.colors});
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (a, b) => a + b);
    final rect = Offset.zero & size;
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round..color = _line;
    canvas.drawArc(rect.deflate(9), 0, 6.28318, false, base);
    if (total <= 0) return;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 12..strokeCap = StrokeCap.round;
    var start = -1.5708;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * 6.28318;
      paint.color = colors[i];
      canvas.drawArc(rect.deflate(9), start, (sweep - .035).clamp(0.0, 6.28318).toDouble(), false, paint);
      start += sweep;
    }
  }
  @override
  bool shouldRepaint(covariant _RingPainter old) => old.values != values || old.colors != colors;
}
class _NoMatches extends StatelessWidget {
  const _NoMatches();
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _line)),
    child: const Center(child: Text('No records match this filter.', style: TextStyle(color: _muted, fontSize: 12))));
}
class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.query_stats_rounded, color: _teal, size: 48), SizedBox(height: 12),
    Text('Nothing to analyse yet', style: TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w800)),
    SizedBox(height: 5), Text('Add records to see your analytics here.', style: TextStyle(color: _muted, fontSize: 11)),
  ]));
}
class _LoadingPage extends StatelessWidget {
  final String title;
  const _LoadingPage({required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: _bg,
    appBar: AppBar(title: Text(title), backgroundColor: _bg, foregroundColor: _white),
    body: const Center(child: CircularProgressIndicator(color: _teal)));
}
class _ErrorPage extends StatelessWidget {
  final String title, message;
  const _ErrorPage({required this.title, required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(backgroundColor: _bg,
    appBar: AppBar(title: Text(title), backgroundColor: _bg, foregroundColor: _white),
    body: Center(child: Padding(padding: const EdgeInsets.all(24),
      child: Text('Could not load analytics: $message', textAlign: TextAlign.center, style: const TextStyle(color: _muted)))));
}
