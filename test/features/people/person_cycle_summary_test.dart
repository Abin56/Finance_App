import 'package:finance_app/core/payment_schedule/domain/cycle_engine.dart';
import 'package:finance_app/features/people/domain/person_cycle_summary.dart';
import 'package:finance_app/features/people/domain/person_overall_totals.dart';
import 'package:finance_app/features/people/domain/person_timeline_cycle_item.dart';
import 'package:finance_app/features/people/domain/person_timeline_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PersonTimelineEntry _entry({
  required String id,
  required DateTime date,
  double? totalAmount,
  double? paidAmount,
  PersonTimelineStatus? status,
}) {
  return PersonTimelineEntry(
    id: id,
    date: date,
    icon: Icons.circle,
    title: 'Entry',
    signedAmount: totalAmount ?? 0,
    category: PersonTimelineCategory.splitExpense,
    isDeleted: false,
    color: Colors.blue,
    status: status,
    totalAmount: totalAmount,
    paidAmount: paidAmount,
  );
}

void main() {
  group('PersonCycleSummary.from', () {
    test('previous-cycle-pending items feed Outstanding/CarryForward/Remaining and their paid sum', () {
      final previousItem = PersonTimelineCycleItem(
        _entry(id: 'l1', date: DateTime(2026, 6, 20), totalAmount: 1000, paidAmount: 400),
      );
      final result = CycleEngineResult<PersonTimelineCycleItem>(
        previousCyclePending: [previousItem],
        current: const [],
        future: const [],
      );

      final summary = PersonCycleSummary.from(
        cycleResult: result,
        overallTotals: const PersonOverallTotals(totalYouOwe: 0, totalTheyOwe: 0, netBalance: 0),
        netBalance: 0,
      );

      expect(summary.previousOutstanding, 600);
      expect(summary.previousCarryForward, 600);
      expect(summary.previousRemaining, 600);
      expect(summary.previousTotalPaid, 400);
    });

    test('current-cycle items feed TotalSplitExpenses/TotalPaid/Remaining', () {
      final currentItem = PersonTimelineCycleItem(
        _entry(id: 'l1', date: DateTime(2026, 7, 20), totalAmount: 500, paidAmount: 200),
      );
      final result = CycleEngineResult<PersonTimelineCycleItem>(
        previousCyclePending: const [],
        current: [currentItem],
        future: const [],
      );

      final summary = PersonCycleSummary.from(
        cycleResult: result,
        overallTotals: const PersonOverallTotals(totalYouOwe: 0, totalTheyOwe: 0, netBalance: 0),
        netBalance: 0,
      );

      expect(summary.currentTotalSplitExpenses, 500);
      expect(summary.currentTotalPaid, 200);
      expect(summary.currentRemaining, 300);
    });

    test('Overall section passes overallTotals and netBalance through unchanged', () {
      final result = CycleEngineResult<PersonTimelineCycleItem>(
        previousCyclePending: const [],
        current: const [],
        future: const [],
      );

      final summary = PersonCycleSummary.from(
        cycleResult: result,
        overallTotals: const PersonOverallTotals(totalYouOwe: 120, totalTheyOwe: 300, netBalance: 180),
        netBalance: 180,
      );

      expect(summary.totalYouOwe, 120);
      expect(summary.totalTheyOwe, 300);
      expect(summary.netBalance, 180);
    });

    test('an empty cycle result produces all-zero Previous/Current sections', () {
      final result = CycleEngineResult<PersonTimelineCycleItem>(
        previousCyclePending: const [],
        current: const [],
        future: const [],
      );

      final summary = PersonCycleSummary.from(
        cycleResult: result,
        overallTotals: const PersonOverallTotals(totalYouOwe: 0, totalTheyOwe: 0, netBalance: 0),
        netBalance: 0,
      );

      expect(summary.previousOutstanding, 0);
      expect(summary.currentTotalSplitExpenses, 0);
      expect(summary.currentRemaining, 0);
    });
  });
}
