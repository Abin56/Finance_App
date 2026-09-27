import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import '../../domain/loan_category.dart';
import '../../domain/loan_direction.dart';
import '../../domain/loan_status.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_card.dart';
import '../widgets/loan_emi_ui.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/loan_status_filter_chips.dart';
import '../widgets/reverse_origination_dialog.dart';
import 'loans_trash_screen.dart';

/// Full loans list — every loan regardless of status, with search and the
/// primary "add loan" entry point.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({
    super.key,
    this.title = 'Loans',
    this.header,
    this.onAddRequest,
  });

  final String title;

  /// Scrolls above the list — the Loan & EMI summary and Loans / EMIs switch
  /// when this list is hosted inside the unified Loan & EMI screen.
  final Widget? header;

  /// When set, "Add" defers to the unified Loan & EMI chooser instead of
  /// opening the Loan form directly.
  final VoidCallback? onAddRequest;

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  LoanListFilter _statusFilter = LoanListFilter.all;
  LoanDirectionFilter _directionFilter = LoanDirectionFilter.all;
  LoanCategoryFilter _categoryFilter = LoanCategoryFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Loan> _applySearch(
    List<Loan> loans,
    Map<String, String> personNameById,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return loans;
    return loans.where((l) {
      final personName = personNameById[l.personId]?.toLowerCase() ?? '';
      final institutionName = l.institutionName?.toLowerCase() ?? '';
      final loanNumber = l.loanNumber?.toLowerCase() ?? '';
      return (l.name?.toLowerCase().contains(query) ?? false) ||
          personName.contains(query) ||
          institutionName.contains(query) ||
          loanNumber.contains(query);
    }).toList();
  }

  List<Loan> _applyCategoryFilter(List<Loan> loans) {
    switch (_categoryFilter) {
      case LoanCategoryFilter.all:
        return loans;
      case LoanCategoryFilter.personal:
        return loans.where((l) => l.category == LoanCategory.personal).toList();
      case LoanCategoryFilter.institutional:
        return loans
            .where((l) => l.category == LoanCategory.institutional)
            .toList();
    }
  }

  List<Loan> _applyDirectionFilter(List<Loan> loans) {
    switch (_directionFilter) {
      case LoanDirectionFilter.all:
        return loans;
      case LoanDirectionFilter.given:
        return loans.where((l) => l.direction == LoanDirection.given).toList();
      case LoanDirectionFilter.taken:
        return loans.where((l) => l.direction == LoanDirection.taken).toList();
    }
  }

  List<Loan> _applyStatusFilter(List<Loan> loans, WidgetRef ref) {
    if (_statusFilter == LoanListFilter.all) return loans;
    return loans.where((l) {
      final status = ref.watch(loanStatusProvider(l));
      switch (_statusFilter) {
        case LoanListFilter.active:
          return status == LoanStatus.active;
        case LoanListFilter.overdue:
          return status == LoanStatus.overdue;
        case LoanListFilter.closed:
          return status == LoanStatus.closed;
        case LoanListFilter.all:
          return true;
      }
    }).toList();
  }

  void _add() {
    final request = widget.onAddRequest;
    if (request != null) {
      request();
    } else {
      LoanFormSheet.show(context);
    }
  }

  void _clearFilters() => setState(() {
    _statusFilter = LoanListFilter.all;
    _directionFilter = LoanDirectionFilter.all;
    _categoryFilter = LoanCategoryFilter.all;
    _query = '';
    _searching = false;
    _searchController.clear();
  });

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(loanRepositoryProvider);
    final loansAsync = ref.watch(loansStreamProvider);
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final personById = {for (final p in people) p.id: p};
    const sidePadding = EdgeInsets.symmetric(horizontal: AppSizes.lg);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search loans…',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _searching ? 'Close search' : 'Search loans',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) {
                _query = '';
                _searchController.clear();
              }
            }),
          ),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              if (value == 'dashboard') {
                context.push(AppRoutes.loanDashboard);
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoansTrashScreen()),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'dashboard',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.dashboard_outlined),
                  title: Text('Loan dashboard'),
                ),
              ),
              PopupMenuItem(
                value: 'trash',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline_rounded),
                  title: Text('Loans trash'),
                ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'loans_fab',
        onPressed: _add,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Something went wrong: $error')),
        data: (loans) {
          final header = widget.header;
          final headerSliver = SliverToBoxAdapter(
            child: header ?? const SizedBox(height: AppSizes.sm),
          );

          if (loans.isEmpty) {
            return CustomScrollView(
              slivers: [
                headerSliver,
                SliverFillRemaining(
                  child: EmptyState(
                    icon: LoanEmiCopy.loanIcon,
                    title: 'No loans yet',
                    subtitle:
                        'A Loan is money borrowed from a bank, lender or '
                        'person. Add one to track its installments and '
                        "what's left to repay.",
                    action: FilledButton(
                      onPressed: () => LoanFormSheet.show(context),
                      child: const Text('Add a Loan'),
                    ),
                  ),
                ),
              ],
            );
          }

          final personNameById = {for (final p in people) p.id: p.name};
          final searched = _applySearch(loans, personNameById);
          final categoryFiltered = _applyCategoryFilter(searched);
          final directionFiltered = _applyDirectionFilter(categoryFiltered);
          final visible = _applyStatusFilter(directionFiltered, ref);
          // Only offer a filter when it can actually split the list.
          final hasLent = loans.any((l) => l.direction == LoanDirection.given);
          final hasBothCategories =
              loans.any((l) => l.category == LoanCategory.personal) &&
              loans.any((l) => l.category == LoanCategory.institutional);

          return CustomScrollView(
            slivers: [
              headerSliver,
              SliverPadding(
                padding: sidePadding,
                sliver: SliverList.list(
                  children: [
                    if (loans.length > 1)
                      LoanStatusFilterChips(
                        selected: _statusFilter,
                        onChanged: (filter) =>
                            setState(() => _statusFilter = filter),
                      ),
                    if (hasLent) ...[
                      const SizedBox(height: AppSizes.sm),
                      LoanDirectionFilterChips(
                        selected: _directionFilter,
                        onChanged: (filter) =>
                            setState(() => _directionFilter = filter),
                      ),
                    ],
                    if (hasBothCategories) ...[
                      const SizedBox(height: AppSizes.sm),
                      LoanCategoryFilterChips(
                        selected: _categoryFilter,
                        onChanged: (filter) =>
                            setState(() => _categoryFilter = filter),
                      ),
                    ],
                    const SizedBox(height: AppSizes.md),
                    if (visible.isEmpty)
                      EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching loans',
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
                    final loan = visible[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Dismissible(
                        key: ValueKey(loan.id),
                        direction: DismissDirection.endToStart,
                        // A wizard-created Loan whose origination money is
                        // still active is never trashed on its own — it goes
                        // through "Reverse & Delete" (which trashes it), so
                        // the tile is not dismissed here.
                        confirmDismiss: (_) async {
                          if (await reverseOriginationIfMoneyActive(
                            context,
                            ref,
                            loan,
                          )) {
                            return false;
                          }
                          if (!context.mounted) return false;
                          return confirmDelete(context, entityName: 'Loan');
                        },
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
                            Icons.delete_outline_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        onDismissed: (_) async {
                          await repository.softDelete(loan);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('Loan moved to trash'),
                              action: SnackBarAction(
                                label: 'Undo',
                                onPressed: () => repository.restore(loan),
                              ),
                            ),
                          );
                        },
                        child: LoanCard(
                          loan: loan,
                          person: personById[loan.personId],
                          payer: personById[loan.payerPersonId],
                          onTap: () =>
                              context.push('${AppRoutes.loans}/${loan.id}'),
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
}
