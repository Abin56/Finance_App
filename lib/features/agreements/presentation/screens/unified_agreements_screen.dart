import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../core/router/app_routes.dart';
import '../../domain/unified_workspace_model.dart';
import '../providers/unified_finance_agreement_providers.dart';
import '../widgets/unified_agreement_card.dart';
import '../widgets/unified_agreement_summary.dart';

class UnifiedAgreementsScreen extends ConsumerStatefulWidget {
  const UnifiedAgreementsScreen({super.key});

  @override
  ConsumerState<UnifiedAgreementsScreen> createState() =>
      _UnifiedAgreementsScreenState();
}

class _UnifiedAgreementsScreenState
    extends ConsumerState<UnifiedAgreementsScreen> {
  final _searchController = TextEditingController();
  var _filters = const UnifiedWorkspaceFilters();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agreements = ref.watch(unifiedFinanceAgreementsProvider);
    final sourceState = ref.watch(unifiedFinanceAgreementsStateProvider);
    final visible = filterUnifiedAgreements(agreements, _filters);
    final state = unifiedWorkspaceState(agreements.length, visible.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans & Installments'),
        actions: [
          IconButton(
            tooltip: 'Add agreement',
            onPressed: _showAddChoices,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddChoices,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: sourceState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Couldn\'t load agreements',
          subtitle: 'Check your connection and try again.\n$error',
          action: FilledButton.icon(
            onPressed: () => ref.invalidate(unifiedFinanceAgreementsProvider),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ),
        data: (_) => CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSizes.lg,
                AppSizes.md,
                AppSizes.lg,
                AppSizes.md,
              ),
              sliver: SliverList.list(
                children: [
                  UnifiedAgreementSummaryCard(
                    summary: summarizeUnifiedAgreements(agreements),
                  ),
                  const SizedBox(height: AppSizes.lg),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search agreements',
                      hintText: 'Name, provider, person, or account',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _filters.search.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(
                                  () =>
                                      _filters = _filters.copyWith(search: ''),
                                );
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                    onChanged: (value) => setState(
                      () => _filters = _filters.copyWith(search: value),
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterMenu<AgreementFilter>(
                          tooltip: 'Agreement type',
                          value: _filters.agreement,
                          values: AgreementFilter.values,
                          label: _agreementLabel,
                          onChanged: (value) => setState(
                            () =>
                                _filters = _filters.copyWith(agreement: value),
                          ),
                        ),
                        _FilterMenu<DirectionFilter>(
                          tooltip: 'Direction',
                          value: _filters.direction,
                          values: DirectionFilter.values,
                          label: _directionLabel,
                          onChanged: (value) => setState(
                            () =>
                                _filters = _filters.copyWith(direction: value),
                          ),
                        ),
                        _FilterMenu<FundingFilter>(
                          tooltip: 'Funding source',
                          value: _filters.funding,
                          values: FundingFilter.values,
                          label: _fundingLabel,
                          onChanged: (value) => setState(
                            () => _filters = _filters.copyWith(funding: value),
                          ),
                        ),
                        _FilterMenu<StatusFilter>(
                          tooltip: 'Status',
                          value: _filters.status,
                          values: StatusFilter.values,
                          label: _statusLabel,
                          onChanged: (value) => setState(
                            () => _filters = _filters.copyWith(status: value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (state == UnifiedWorkspaceState.empty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.account_balance_outlined,
                  title: 'No agreements yet',
                  subtitle:
                      'Add money you borrowed, money you lent, or an installment purchase.',
                  action: FilledButton.icon(
                    onPressed: _showAddChoices,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add agreement'),
                  ),
                ),
              )
            else if (state == UnifiedWorkspaceState.noResults)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'No matching agreements',
                  subtitle: 'Try another search or change a filter.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.lg,
                  0,
                  AppSizes.lg,
                  AppSizes.fabClearance,
                ),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSizes.md),
                  itemBuilder: (context, index) {
                    final agreement = visible[index];
                    return UnifiedAgreementCard(
                      agreement: agreement,
                      onTap: () => context.push(agreementDetailPath(agreement)),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddChoices() async {
    final choice = await showModalBottomSheet<_AddChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Add an agreement'),
              subtitle: Text('Choose what you want to track.'),
            ),
            ListTile(
              leading: const Icon(Icons.south_west_rounded),
              title: const Text('Money I borrowed'),
              onTap: () => Navigator.pop(context, _AddChoice.borrowed),
            ),
            ListTile(
              leading: const Icon(Icons.north_east_rounded),
              title: const Text('Money I lent'),
              onTap: () => Navigator.pop(context, _AddChoice.lent),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_bag_outlined),
              title: const Text('Installment purchase'),
              onTap: () => Navigator.pop(context, _AddChoice.installment),
            ),
            const SizedBox(height: AppSizes.sm),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final kind = switch (choice) {
      _AddChoice.borrowed => 'borrowed',
      _AddChoice.lent => 'lent',
      _AddChoice.installment => 'installmentPurchase',
    };
    await context.push('${AppRoutes.addAgreement}?kind=$kind');
  }
}

enum _AddChoice { borrowed, lent, installment }

class _FilterMenu<T> extends StatelessWidget {
  const _FilterMenu({
    required this.tooltip,
    required this.value,
    required this.values,
    required this.label,
    required this.onChanged,
  });

  final String tooltip;
  final T value;
  final List<T> values;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: AppSizes.sm),
    child: PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final option in values)
          PopupMenuItem(value: option, child: Text(label(option))),
      ],
      child: Chip(
        avatar: const Icon(Icons.tune_rounded, size: 16),
        label: Text(label(value)),
      ),
    ),
  );
}

String _agreementLabel(AgreementFilter value) => switch (value) {
  AgreementFilter.all => 'All types',
  AgreementFilter.loan => 'Loans',
  AgreementFilter.installmentPurchase => 'Installments',
};

String _directionLabel(DirectionFilter value) => switch (value) {
  DirectionFilter.all => 'All directions',
  DirectionFilter.borrowed => 'Borrowed',
  DirectionFilter.lent => 'Lent',
};

String _fundingLabel(FundingFilter value) => switch (value) {
  FundingFilter.all => 'All funding',
  FundingFilter.bank => 'Bank',
  FundingFilter.financeCompany => 'Finance company',
  FundingFilter.creditCard => 'Credit card',
  FundingFilter.person => 'Person',
  FundingFilter.other => 'Other',
};

String _statusLabel(StatusFilter value) => switch (value) {
  StatusFilter.all => 'All statuses',
  StatusFilter.active => 'Active',
  StatusFilter.dueSoon => 'Due soon',
  StatusFilter.overdue => 'Overdue',
  StatusFilter.defaulted => 'Defaulted',
  StatusFilter.closed => 'Closed',
};
