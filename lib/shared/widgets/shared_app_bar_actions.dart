import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:my_finance/core/preferences/general_preferences.dart';

import 'package:my_finance/modules/finance/models/budgets_model.dart';
import 'package:my_finance/modules/finance/services/budgets_service.dart';
import 'package:my_finance/features/search/screens/global_search_screen.dart';
import 'package:my_finance/app/screens/modules_tools_page.dart';

/// Har main section ke liye mushtarka notifications aur Modules & Tools actions banata hai.
List<Widget> buildSharedAppBarActions(BuildContext context) {
  return [
    IconButton(
      tooltip: 'Global Search',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
      ),
      icon: const Icon(Icons.search_rounded),
    ),
    IconButton(
      tooltip: 'Notifications',
      onPressed: () => _showBudgetAlerts(context),
      icon: const Icon(Icons.notifications_none_rounded),
    ),
    IconButton(
      tooltip: 'Modules & Tools',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ModulesToolsPage()),
      ),
      icon: Transform.translate(
        offset: const Offset(-2, 0),
        child: const _CombineIcon(),
      ),
    ),
  ];
}

void _showBudgetAlerts(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: Theme.of(context).colorScheme.primary),
              SizedBox(width: 9),
              Text('Budget Notifications',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: FutureBuilder<List<BudgetsModel>>(
              future: BudgetsService.getBudgets(activeOnly: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Unable to load budget alerts: ${snapshot.error}'),
                  );
                }
                final alerts = (snapshot.data ?? [])
                    .where((budget) =>
                        budget.isCurrentlyActive &&
                        budget.limitAmount > 0 &&
                        budget.spentAmount / budget.limitAmount >= 0.5)
                    .toList()
                  ..sort((a, b) => (b.spentAmount / b.limitAmount)
                      .compareTo(a.spentAmount / a.limitAmount));

                if (alerts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 38, color: Theme.of(context).colorScheme.secondary),
                          SizedBox(height: 10),
                          Text('You are all caught up',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.onSurface)),
                          SizedBox(height: 4),
                          Text('No active budget has reached 50% usage.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: alerts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final budget = alerts[index];
                    final ratio = budget.spentAmount / budget.limitAmount;
                    final percent = ratio * 100;
                    final color = ratio >= 1
                        ? Theme.of(context).colorScheme.error
                        : ratio >= 0.9
                            ? Theme.of(context).colorScheme.tertiary
                            : ratio >= 0.75
                                ? Theme.of(context).colorScheme.tertiary
                                : Theme.of(context).colorScheme.primary;
                    final status = ratio >= 1
                        ? 'Budget limit reached'
                        : ratio >= 0.9
                            ? 'Almost exceeded'
                            : ratio >= 0.75
                                ? '75% of budget used'
                                : '50% of budget used';
                    final format = NumberFormat('#,##0.00');
                    return Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: color.withValues(alpha: 0.22)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(budget.name,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Theme.of(context).colorScheme.onSurface)),
                              ),
                              Text('${percent.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: color)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(status,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: color)),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: ratio.clamp(0.0, 1.0).toDouble(),
                              minHeight: 6,
                              backgroundColor: Theme.of(context).colorScheme.outlineVariant,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                          const SizedBox(height: 7),
                          FutureBuilder<bool>(
                            future: GeneralPreferences.instance.hideBalances,
                            builder: (context, snapshot) {
                              final hidden = snapshot.connectionState != ConnectionState.done || (snapshot.data ?? false);
                              return Text(
                                hidden
                                    ? '${budget.currency} •••••• / ••••••'
                                    : '${budget.currency} ${format.format(budget.spentAmount)} / ${format.format(budget.limitAmount)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Theme.of(context).hintColor,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}

/// App-bar actions retained for the original main navigation sections.
List<Widget> buildMainSectionAppBarActions(BuildContext context) {
  return [
    IconButton(
      tooltip: 'Global Search',
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const GlobalSearchScreen()),
      ),
      icon: const Icon(Icons.search_rounded),
    ),
    IconButton(
      tooltip: 'Notifications',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No new notifications'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      icon: const Icon(Icons.notifications_none_rounded),
    ),
    IconButton(
      tooltip: 'Modules & Tools',
      onPressed: () => Navigator.pushNamed(context, '/modules-tools'),
      icon: Transform.translate(
        offset: const Offset(-2, 0),
        child: const _CombineIcon(),
      ),
    ),
  ];
}


/// Lucide-style Combine icon used for the Modules & Tools action.
class _CombineIcon extends StatelessWidget {
  const _CombineIcon();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ??
        Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      size: const Size(24, 24),
      painter: _CombineIconPainter(color),
    );
  }
}

class _CombineIconPainter extends CustomPainter {
  const _CombineIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final topRightOne = Path()
      ..moveTo(14, 3)
      ..cubicTo(14.552, 3, 15, 3.448, 15, 4)
      ..lineTo(15, 9)
      ..cubicTo(15, 9.552, 14.552, 10, 14, 10);
    final topRightTwo = Path()
      ..moveTo(19, 3)
      ..cubicTo(19.552, 3, 20, 3.448, 20, 4)
      ..lineTo(20, 9)
      ..cubicTo(20, 9.552, 19.552, 10, 19, 10);
    final lowerLeft = Path()
      ..moveTo(7, 15)
      ..lineTo(10, 18)
      ..moveTo(7, 21)
      ..lineTo(10, 18)
      ..lineTo(5, 18)
      ..cubicTo(3.895, 18, 3, 17.105, 3, 16)
      ..lineTo(3, 14);

    canvas.drawPath(topRightOne, paint);
    canvas.drawPath(topRightTwo, paint);
    canvas.drawPath(lowerLeft, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(14, 14, 7, 7),
        const Radius.circular(1),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(3, 3, 7, 7),
        const Radius.circular(1),
      ),
      paint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CombineIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
