import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/budgets_model.dart';
import '../services/budgets_service.dart';

/// Consistent notification and settings actions for every main section.
List<Widget> buildSharedAppBarActions(BuildContext context) {
  return [
    IconButton(
      tooltip: 'Notifications',
      onPressed: () => _showBudgetAlerts(context),
      icon: const Icon(Icons.notifications_none_rounded),
    ),
    IconButton(
      tooltip: 'Settings',
      onPressed: () => Navigator.pushNamed(context, '/settings'),
      icon: const Icon(Icons.settings_outlined),
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
      decoration: const BoxDecoration(
        color: Colors.white,
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
                color: const Color(0xFFD9E0DC),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Icon(Icons.notifications_active_outlined,
                  color: Color(0xFF147D59)),
              SizedBox(width: 9),
              Text('Budget Notifications',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF202A26))),
            ],
          ),
          const SizedBox(height: 14),
          Flexible(
            child: FutureBuilder<List<BudgetsModel>>(
              future: BudgetsService.getBudgets(activeOnly: true),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
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
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 38, color: Color(0xFF16865B)),
                          SizedBox(height: 10),
                          Text('You are all caught up',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF202A26))),
                          SizedBox(height: 4),
                          Text('No active budget has reached 50% usage.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF7B8781))),
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
                        ? const Color(0xFFD9534F)
                        : ratio >= 0.9
                            ? const Color(0xFFE18A35)
                            : ratio >= 0.75
                                ? const Color(0xFFCC9A35)
                                : const Color(0xFF147D59);
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
                        color: const Color(0xFFF8FAF9),
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF202A26))),
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
                              backgroundColor: const Color(0xFFE8EEEA),
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(color),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            '${budget.currency} ${format.format(budget.spentAmount)} / ${format.format(budget.limitAmount)}',
                            style: const TextStyle(
                                fontSize: 10, color: Color(0xFF7B8781)),
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
