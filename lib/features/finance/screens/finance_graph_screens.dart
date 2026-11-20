import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/features/finance/models/assets_model.dart';
import 'package:my_finance/features/finance/models/loans_model.dart';
import 'package:my_finance/features/finance/services/assets_service.dart';
import 'package:my_finance/features/finance/services/loans_service.dart';

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
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _GraphLoadingPage(title: 'Assets Analytics');
      }
      if (snapshot.hasError) {
        return _GraphErrorPage(title: 'Assets Analytics', message: snapshot.error.toString());
      }
      final assets = snapshot.data ?? const <AssetsModel>[];
      final entries = assets.map((asset) => _GraphEntry(
        name: asset.name,
        currency: asset.currency,
        value: asset.isSold ? (asset.salePrice ?? 0) : asset.currentValue,
        secondaryValue: asset.purchasePrice,
        status: asset.isSold ? 'Sold' : 'Active',
        detail: asset.category,
      )).toList();
      return _AnalyticsPage(
        title: 'Assets Analytics',
        subtitle: 'Asset value, purchase cost and status by currency',
        icon: Icons.account_balance_rounded,
        entries: entries,
        hideBalances: widget.hideBalances,
        primaryLabel: 'Tracked assets',
        valueLabel: 'Current / sale value',
        secondaryLabel: 'Purchase value',
      );
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
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const _GraphLoadingPage(title: 'Loans Analytics');
      }
      if (snapshot.hasError) {
        return _GraphErrorPage(title: 'Loans Analytics', message: snapshot.error.toString());
      }
      final loans = snapshot.data ?? const <LoansModel>[];
      final entries = loans.map((loan) {
        final status = loan.isOverdue ? 'Overdue' : (loan.isPaid ? 'Paid' : 'Active');
        return _GraphEntry(
          name: loan.partyId == null ? 'Loan #${loan.id ?? '-'}' : 'Loan #${loan.id ?? '-'}',
          currency: loan.currency,
          value: loan.remainingAmount,
          secondaryValue: loan.amount,
          status: status,
          detail: loan.loanType == 'given' ? 'Receivable' : 'Payable',
        );
      }).toList();
      return _AnalyticsPage(
        title: 'Loans Analytics',
        subtitle: 'Outstanding balances, original amounts and repayment status',
        icon: Icons.account_balance_wallet_rounded,
        entries: entries,
        hideBalances: widget.hideBalances,
        primaryLabel: 'Total loans',
        valueLabel: 'Outstanding',
        secondaryLabel: 'Original amount',
      );
    },
  );
}

class _GraphEntry {
  final String name;
  final String currency;
  final double value;
  final double secondaryValue;
  final String status;
  final String detail;
  const _GraphEntry({
    required this.name,
    required this.currency,
    required this.value,
    required this.secondaryValue,
    required this.status,
    required this.detail,
  });
}

class _AnalyticsPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<_GraphEntry> entries;
  final bool hideBalances;
  final String primaryLabel;
  final String valueLabel;
  final String secondaryLabel;

  const _AnalyticsPage({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.entries,
    required this.hideBalances,
    required this.primaryLabel,
    required this.valueLabel,
    required this.secondaryLabel,
  });

  String _money(double value) => hideBalances ? '••••••' : NumberFormat('#,##0.00').format(value);

  @override
  Widget build(BuildContext context) {
    final currencies = entries.map((e) => e.currency.toUpperCase()).toSet().toList()..sort();
    final activeCount = entries.where((e) => e.status == 'Active').length;
    final closedCount = entries.where((e) => e.status == 'Sold' || e.status == 'Paid').length;
    final overdueCount = entries.where((e) => e.status == 'Overdue').length;
    final palette = [
      const Color(0xFF5B6CFF),
      const Color(0xFF00A88F),
      const Color(0xFFFFA62B),
      const Color(0xFFE45C8A),
      const Color(0xFF8A63D2),
      const Color(0xFF2698D6),
    ];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: entries.isEmpty
        ? Center(child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 54, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              const Text('Nothing to chart yet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('Add records to see your analytics here.', textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).hintColor)),
            ]),
          ))
        : ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF263C91), Color(0xFF6656C8), Color(0xFFB14F91)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: const Color(0xFF5145B5).withValues(alpha: .18), blurRadius: 20, offset: const Offset(0, 9))],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 42, height: 42,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: Colors.white, size: 22)),
                    const SizedBox(width: 11),
                    Expanded(child: Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: .88), fontSize: 12, fontWeight: FontWeight.w600))),
                    const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 24),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: [
                    _TopMetric(label: primaryLabel, value: '${entries.length}', color: Colors.white),
                    _TopMetric(label: 'Currencies', value: '${currencies.length}', color: Colors.white),
                    _TopMetric(label: 'Active', value: '$activeCount', color: Colors.white),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Status distribution',
                subtitle: 'Record count across all currencies',
                child: Row(children: [
                  SizedBox(
                    width: 116,
                    height: 116,
                    child: CustomPaint(
                      painter: _StatusRingPainter(
                        values: [activeCount.toDouble(), closedCount.toDouble(), overdueCount.toDouble()],
                        colors: [const Color(0xFF00A88F), const Color(0xFF5B6CFF), const Color(0xFFFFA62B)],
                      ),
                      child: Center(child: Text('${entries.length}', style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _LegendRow(color: const Color(0xFF00A88F), label: 'Active', value: activeCount),
                    const SizedBox(height: 9),
                    _LegendRow(color: const Color(0xFF5B6CFF), label: 'Sold / Paid', value: closedCount),
                    if (overdueCount > 0) ...[
                      const SizedBox(height: 9),
                      _LegendRow(color: const Color(0xFFFFA62B), label: 'Overdue', value: overdueCount),
                    ],
                  ])),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                const Expanded(child: Text('Currency breakdown', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900))),
                Text('${currencies.length} groups', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 9),
              for (var i = 0; i < currencies.length; i++)
                _CurrencyGraphCard(
                  currency: currencies[i],
                  entries: entries.where((e) => e.currency.toUpperCase() == currencies[i]).toList(),
                  color: palette[i % palette.length],
                  money: _money,
                  valueLabel: valueLabel,
                  secondaryLabel: secondaryLabel,
                ),
            ],
          ),
    );
  }
}

class _TopMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _TopMetric({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w900)),
    const SizedBox(height: 2),
    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color.withValues(alpha: .78), fontSize: 10, fontWeight: FontWeight.w600)),
  ]));
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _SectionCard({required this.title, required this.subtitle, required this.child});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .7)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
      const SizedBox(height: 3),
      Text(subtitle, style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
      const SizedBox(height: 14),
      child,
    ]),
  );
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _LegendRow({required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 8),
    Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
    Text('$value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
  ]);
}

class _CurrencyGraphCard extends StatelessWidget {
  final String currency;
  final List<_GraphEntry> entries;
  final Color color;
  final String Function(double) money;
  final String valueLabel;
  final String secondaryLabel;
  const _CurrencyGraphCard({
    required this.currency,
    required this.entries,
    required this.color,
    required this.money,
    required this.valueLabel,
    required this.secondaryLabel,
  });

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);
    final secondaryTotal = entries.fold<double>(0, (sum, e) => sum + e.secondaryValue);
    final maxValue = entries.fold<double>(0, (max, e) => e.value > max ? e.value : max);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 35, height: 35,
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(11)),
            child: Center(child: Text(currency, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: color)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(currency, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
            Text('${entries.length} records', style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor)),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money(total), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: color)),
            Text(valueLabel, style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor)),
          ]),
        ]),
        const SizedBox(height: 11),
        Row(children: [
          Expanded(child: Text(secondaryLabel, style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor))),
          Text(money(secondaryTotal), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 14),
        for (final entry in entries) ...[
          Row(children: [
            Expanded(child: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            Text(money(entry.value), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LayoutBuilder(builder: (context, constraints) {
              final ratio = maxValue <= 0 ? 0.0 : (entry.value / maxValue).clamp(0.0, 1.0).toDouble();
              return Stack(children: [
                Container(height: 8, width: constraints.maxWidth, color: Theme.of(context).colorScheme.surfaceContainerHighest),
                Container(
                  height: 8,
                  width: constraints.maxWidth * ratio,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [color.withValues(alpha: .55), color]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ]);
            }),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Text(entry.detail, style: TextStyle(fontSize: 9, color: Theme.of(context).hintColor)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
              child: Text(entry.status, style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w800)),
            ),
          ]),
          if (entry != entries.last) const Divider(height: 18),
        ],
      ]),
    );
  }
}

class _StatusRingPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  const _StatusRingPainter({required this.values, required this.colors});
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (sum, value) => sum + value);
    final rect = Offset.zero & size;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = 13..strokeCap = StrokeCap.round;
    if (total <= 0) {
      paint.color = colors.first.withValues(alpha: .18);
      canvas.drawArc(rect.deflate(9), 0, 6.28318, false, paint);
      return;
    }
    var start = -1.5708;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = values[i] / total * 6.28318;
      paint.shader = SweepGradient(colors: [colors[i].withValues(alpha: .65), colors[i]]).createShader(rect);
      canvas.drawArc(rect.deflate(9), start, sweep - .035, false, paint);
      paint.shader = null;
      start += sweep;
    }
  }
  @override
  bool shouldRepaint(covariant _StatusRingPainter oldDelegate) =>
    oldDelegate.values != values || oldDelegate.colors != colors;
}

class _GraphLoadingPage extends StatelessWidget {
  final String title;
  const _GraphLoadingPage({required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: const Center(child: CircularProgressIndicator()),
  );
}

class _GraphErrorPage extends StatelessWidget {
  final String title;
  final String message;
  const _GraphErrorPage({required this.title, required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text('Could not load analytics: $message', textAlign: TextAlign.center),
    )),
  );
}
