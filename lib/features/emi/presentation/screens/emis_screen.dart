import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../lending/presentation/widgets/loan_emi_ui.dart';
import '../../domain/emi.dart';
import '../../domain/emi_loan_type.dart';
import '../../domain/emi_status.dart';
import '../providers/emi_providers.dart';
import '../widgets/emi_form_sheet.dart';
import '../widgets/emi_status_filter_chips.dart';
import '../widgets/emi_tile.dart';
import 'emis_trash_screen.dart';

/// Full EMI list — every EMI regardless of status, with search and the
/// primary "add EMI" entry point.
class EmisScreen extends ConsumerStatefulWidget {
  const EmisScreen({
    super.key,
    this.title = 'EMIs',
    this.header,
    this.onAddRequest,
  });

  final String title;

  /// Scrolls above the list — the Loan & EMI summary and Loans / EMIs switch
  /// when this list is hosted inside the unified Loan & EMI screen.
  final Widget? header;

  /// When set, "Add" defers to the unified Loan & EMI chooser instead of
  /// opening the EMI form directly.
  final VoidCallback? onAddRequest;

  @override
  ConsumerState<EmisScreen> createState() => _EmisScreenState();
}

class _EmisScreenState extends ConsumerState<EmisScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  EmiListFilter _statusFilter = EmiListFilter.all;
  EmiLoanType? _loanTypeFilter;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Emi> _applySearch(List<Emi> emis) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return emis;
    return emis.where((e) {
      return e.name.toLowerCase().contains(query) ||
          (e.lenderName?.toLowerCase().contains(query) ?? false) ||
          (e.loanNumber?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  List<Emi> _applyFilters(List<Emi> emis, WidgetRef ref) {
    var filtered = emis;
    if (_loanTypeFilter != null) {
      filtered = filtered.where((e) => e.loanType == _loanTypeFilter).toList();
    }
    if (_statusFilter == EmiListFilter.all) return filtered;
    if (_statusFilter == EmiListFilter.upcoming) {
      return filtered
          .where((e) => ref.watch(dueThisMonthEmisProvider).contains(e))
          .toList();
    }
    return filtered.where((e) {
      final status = ref.watch(emiStatusProvider(e));
      switch (_statusFilter) {
        case EmiListFilter.active:
          return status == EmiStatus.active;
        case EmiListFilter.overdue:
          return status == EmiStatus.overdue;
        case EmiListFilter.defaulted:
          return status == EmiStatus.defaulted;
        case EmiListFilter.completed:
          return status == EmiStatus.completed;
        case EmiListFilter.closed:
          return status == EmiStatus.closed;
        case EmiListFilter.all:
        case EmiListFilter.upcoming:
          return true;
      }
    }).toList();
  }

  void _add() {
    final request = widget.onAddRequest;
    if (request != null) {
      request();
    } else {
      EmiFormSheet.show(context);
    }
  }

  void _clearFilters() => setState(() {
    _statusFilter = EmiListFilter.all;
    _loanTypeFilter = null;
    _query = '';
    _searching = false;
    _searchController.clear();
  });

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(emiRepositoryProvider);
    final emisAsync = ref.watch(emisStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search EMIs…',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search EMIs',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'EMIs trash',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const EmisTrashScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'emis_fab',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: emisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
        data: (emis) {
          final headerSliver = SliverToBoxAdapter(
            child: widget.header ?? const SizedBox(height: AppSizes.sm),
          );

          if (emis.isEmpty) {
            return CustomScrollView(
              slivers: [
                headerSliver,
                SliverFillRemaining(
                  child: EmptyState(
                    icon: LoanEmiCopy.emiIcon,
                    title: 'No EMIs yet',
                    subtitle:
                        'An EMI is a purchase or Credit Card EMI you pay back '
                        "in fixed installments. Add one to see what's due "
                        "and what's left.",
                    action: FilledButton(
                      onPressed: () => EmiFormSheet.show(context),
                      child: const Text('Add an EMI'),
                    ),
                  ),
                ),
              ],
            );
          }

          final searched = _applySearch(emis);
          final visible = _applyFilters(searched, ref);
          // Only offer the type filter when the list actually has variety.
          final types = {for (final e in emis) e.loanType}.toList()
            ..sort((a, b) => a.index.compareTo(b.index));

          return CustomScrollView(
            slivers: [
              headerSliver,
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                sliver: SliverList.list(
                  children: [
                    if (emis.length > 1)
                      EmiStatusFilterChips(
                        selected: _statusFilter,
                        onChanged: (filter) =>
                            setState(() => _statusFilter = filter),
                      ),
                    if (types.length > 1) ...[
                      const SizedBox(height: AppSizes.sm),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _typeChip('All types', null),
                            for (final type in types)
                              _typeChip(type.label, type),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSizes.md),
                    if (visible.isEmpty)
                      EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching EMIs',
                        subtitle: 'Try a different search or filter.',
                        action: TextButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters'),
                        ),
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  0,
                  AppSizes.lg,
                  AppSizes.fabClearance,
                ),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final emi = visible[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Dismissible(
                        key: ValueKey(emi.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            confirmDelete(context, entityName: 'EMI'),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.lg,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusLg,
                            ),
                          ),
                          child: Icon(
                            Icons.archive_outlined,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onDismissed: (_) async {
                          await repository.softDelete(emi);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('EMI archived'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => repository.restore(emi),
                              ),
                            ),
                          );
                        },
                        child: EmiTile(
                          emi: emi,
                          onTap: () =>
                              context.push('${AppRoutes.emis}/${emi.id}'),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _typeChip(String label, EmiLoanType? type) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSizes.xs),
      child: ChoiceChip(
        label: Text(label),
        selected: _loanTypeFilter == type,
        onSelected: (_) => setState(() => _loanTypeFilter = type),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        ),
      ),
    );
  }
}
