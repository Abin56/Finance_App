import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
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
  const EmisScreen({super.key});

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
      return filtered.where((e) => ref.watch(dueThisMonthEmisProvider).contains(e)).toList();
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
        case EmiListFilter.closed:
          return status == EmiStatus.closed;
        case EmiListFilter.all:
        case EmiListFilter.upcoming:
          return true;
      }
    }).toList();
  }

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
                decoration: const InputDecoration(hintText: 'Search EMIs…', border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('EMIs'),
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
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Trash',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const EmisTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'emis_fab',
        onPressed: () => EmiFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: emisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (emis) {
          if (emis.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No EMIs yet',
              subtitle: 'Add an EMI to start tracking your monthly payments.',
              action: FilledButton(
                onPressed: () => EmiFormSheet.show(context),
                child: const Text('Add your first EMI'),
              ),
            );
          }

          final searched = _applySearch(emis);
          final visible = _applyFilters(searched, ref);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, 0),
                sliver: SliverList.list(
                  children: [
                    EmiStatusFilterChips(
                      selected: _statusFilter,
                      onChanged: (filter) => setState(() => _statusFilter = filter),
                    ),
                    const SizedBox(height: AppSizes.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: AppSizes.xs),
                            child: ChoiceChip(
                              label: const Text('All loan types'),
                              selected: _loanTypeFilter == null,
                              onSelected: (_) => setState(() => _loanTypeFilter = null),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
                            ),
                          ),
                          for (final type in EmiLoanType.values)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSizes.xs),
                              child: ChoiceChip(
                                label: Text(type.label),
                                selected: _loanTypeFilter == type,
                                onSelected: (_) => setState(() => _loanTypeFilter = type),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSizes.radiusPill)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSizes.lg),
                    if (visible.isEmpty)
                      const EmptyState(
                        icon: Icons.search_off_rounded,
                        title: 'No matching EMIs',
                        subtitle: 'Try a different search or filter.',
                      ),
                  ],
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSizes.lg, 0, AppSizes.lg, AppSizes.md),
                sliver: SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final emi = visible[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSizes.sm),
                      child: Dismissible(
                        key: ValueKey(emi.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => confirmDelete(context, entityName: 'EMI'),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                          ),
                          child: Icon(Icons.archive_outlined, color: Theme.of(context).colorScheme.error),
                        ),
                        onDismissed: (_) async {
                          await repository.softDelete(emi);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('EMI archived'),
                              action: SnackBarAction(label: 'Undo', onPressed: () => repository.restore(emi)),
                            ),
                          );
                        },
                        child: EmiTile(
                          emi: emi,
                          onTap: () => context.push('${AppRoutes.emis}/${emi.id}'),
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
