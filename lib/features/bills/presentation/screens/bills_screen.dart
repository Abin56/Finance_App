import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../domain/bill.dart';
import '../../domain/bill_status.dart';
import '../providers/bill_providers.dart';
import '../widgets/bill_filter.dart';
import '../widgets/bill_filter_sheet.dart';
import '../widgets/bill_form_sheet.dart';
import '../widgets/bill_tile.dart';
import 'bills_trash_screen.dart';

/// Full bill list, grouped by status (Overdue / Due Today / Upcoming /
/// Partially Paid / Paid / Skipped) — mirrors [TransactionsScreen]'s
/// search+filter chrome, grouped by status instead of by date.
class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});

  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  BillFilter _filter = const BillFilter();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final result = await BillFilterSheet.show(context, _filter);
    if (result != null) setState(() => _filter = result);
  }

  List<Bill> _applyFilters(List<Bill> bills, Map<String, String> categoryNamesById) {
    final query = _query.trim().toLowerCase();

    return bills.where((b) {
      if (_filter.status != null && b.status != _filter.status) return false;
      if (_filter.categoryId != null && b.categoryId != _filter.categoryId) return false;
      if (_filter.accountId != null && b.accountId != _filter.accountId) return false;
      if (_filter.startDate != null && b.dueDate.isBefore(_filter.startDate!)) return false;
      if (_filter.endDate != null && b.dueDate.isAfter(_filter.endDate!)) return false;

      if (query.isEmpty) return true;
      final categoryName = categoryNamesById[b.categoryId] ?? '';
      return b.name.toLowerCase().contains(query) ||
          b.notes.toLowerCase().contains(query) ||
          categoryName.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final billsAsync = ref.watch(billsStreamProvider);
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final categoryNamesById = {for (final c in categories) c.id: c.name};

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search bills…', border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('Bills'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            icon: Icon(
              _filter.isActive ? Icons.filter_alt_rounded : Icons.filter_alt_outlined,
              color: _filter.isActive ? Theme.of(context).colorScheme.primary : null,
            ),
            tooltip: 'Filters',
            onPressed: _openFilters,
          ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Calendar',
            onPressed: () => context.push(AppRoutes.calendar),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BillsTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'bills_fab',
        onPressed: () => BillFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: billsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (bills) {
          if (bills.isEmpty) {
            return EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No bills yet',
              subtitle: 'Add a recurring or one-time bill to start tracking due dates.',
              action: FilledButton(
                onPressed: () => BillFormSheet.show(context),
                child: const Text('Add your first bill'),
              ),
            );
          }

          final visible = _applyFilters(bills, categoryNamesById);
          if (visible.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching bills',
              subtitle: 'Try a different search term or clear your filters.',
            );
          }

          final grouped = <BillStatus, List<Bill>>{};
          for (final bill in visible) {
            grouped.putIfAbsent(bill.status, () => []).add(bill);
          }

          const statusOrder = [
            BillStatus.overdue,
            BillStatus.dueToday,
            BillStatus.partiallyPaid,
            BillStatus.upcoming,
            BillStatus.skipped,
            BillStatus.paid,
          ];

          // Flatten to header/row slots once per build so itemBuilder stays
          // O(1) and only visible rows get built, rather than materializing
          // every status group's tiles up front regardless of scroll position.
          final slots = <Object>[];
          for (final status in statusOrder) {
            final group = grouped[status];
            if (group == null) continue;
            slots.add(status);
            slots.addAll(group);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSizes.lg),
            itemCount: slots.length,
            itemBuilder: (context, index) {
              final slot = slots[index];
              if (slot is BillStatus) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm, top: AppSizes.sm),
                  child: Row(
                    children: [
                      Icon(slot.icon, size: AppSizes.iconSm, color: slot.color),
                      const SizedBox(width: AppSizes.xs),
                      Text(
                        '${slot.label} (${grouped[slot]!.length})',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: slot.color),
                      ),
                    ],
                  ),
                );
              }
              final bill = slot as Bill;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSizes.sm),
                child: Dismissible(
                  key: ValueKey(bill.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => confirmDelete(context, entityName: 'Bill'),
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onDismissed: (_) => _softDeleteWithUndo(bill),
                  child: BillTile(
                    bill: bill,
                    category: categoriesById[bill.categoryId],
                    onTap: () => context.push('${AppRoutes.bills}/${bill.id}'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _softDeleteWithUndo(Bill bill) async {
    final repository = ref.read(billRepositoryProvider);
    await repository.softDelete(bill);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${bill.name} moved to trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.restore(bill),
        ),
      ),
    );
  }
}
