import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_form_sheet.dart';
import '../widgets/loan_tile.dart';
import 'loans_trash_screen.dart';

/// Full loans list — every loan regardless of status, with search and the
/// primary "add loan" entry point.
class LoansScreen extends ConsumerStatefulWidget {
  const LoansScreen({super.key});

  @override
  ConsumerState<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends ConsumerState<LoansScreen> {
  final _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Loan> _applySearch(List<Loan> loans, Map<String, String> personNameById) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return loans;
    return loans.where((l) {
      final personName = personNameById[l.personId]?.toLowerCase() ?? '';
      return (l.name?.toLowerCase().contains(query) ?? false) || personName.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(loanRepositoryProvider);
    final loansAsync = ref.watch(loansStreamProvider);
    final people = ref.watch(peopleStreamProvider).value ?? const [];
    final personById = {for (final p in people) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search loans…', border: InputBorder.none),
                onChanged: (value) => setState(() => _query = value),
              )
            : const Text('Loans'),
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
              MaterialPageRoute(builder: (_) => const LoansTrashScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'loans_fab',
        onPressed: () => LoanFormSheet.show(context),
        child: const Icon(Icons.add),
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (loans) {
          if (loans.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No loans yet',
              subtitle: 'Add a loan to start tracking money you\'ve lent.',
              action: FilledButton(
                onPressed: () => LoanFormSheet.show(context),
                child: const Text('Add your first loan'),
              ),
            );
          }

          final personNameById = {for (final p in people) p.id: p.name};
          final visible = _applySearch(loans, personNameById);
          if (visible.isEmpty) {
            return const EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No matching loans',
              subtitle: 'Try a different search term.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSizes.lg),
            children: [
              for (final loan in visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: Dismissible(
                    key: ValueKey(loan.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => confirmDelete(context, entityName: 'Loan'),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                      ),
                      child: Icon(Icons.delete_outline_rounded, color: Theme.of(context).colorScheme.error),
                    ),
                    onDismissed: (_) async {
                      await repository.softDelete(loan);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Loan moved to trash'),
                          action: SnackBarAction(label: 'Undo', onPressed: () => repository.restore(loan)),
                        ),
                      );
                    },
                    child: LoanTile(
                      loan: loan,
                      person: personById[loan.personId],
                      onTap: () => context.push('${AppRoutes.loans}/${loan.id}'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
