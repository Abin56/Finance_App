import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/states/empty_state.dart';
import '../../../../shared/widgets/states/transaction_kind_badge.dart';
import '../../domain/search_result.dart';
import '../providers/search_providers.dart';

/// Global Search — one box across transactions, shared expenses, people,
/// bills, EMI, loans, credit cards, accounts and categories. Read-only and
/// navigational: every row deep-links into the feature screen that owns the
/// record, so Search never becomes a second place to edit things.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Debounced so a fast typist doesn't re-fold every feature's collection
  /// on each keystroke — [searchResultsProvider] rebuilds only once typing
  /// pauses. The `setState` is for the clear button alone: it tracks the
  /// controller, which changes on every keystroke rather than on the
  /// debounced query.
  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) ref.read(searchQueryProvider.notifier).state = value;
    });
  }

  void _clear() {
    _debounce?.cancel();
    setState(_controller.clear);
    ref.read(searchQueryProvider.notifier).state = '';
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: 'Search anything…',
            suffixIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Clear',
                    onPressed: _clear,
                  ),
          ),
        ),
      ),
      body: _body(query, results),
    );
  }

  Widget _body(String query, List<SearchResult> results) {
    if (query.trim().isEmpty) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Search everything',
        subtitle: 'Find a transaction, person, bill, EMI, loan, card, account or category — '
            'by name, note, or amount.',
      );
    }

    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No matches for "${query.trim()}"',
        subtitle: 'Check the spelling, or try an amount or a person\'s name instead.',
        action: TextButton(onPressed: _clear, child: const Text('Clear search')),
      );
    }

    return _GroupedResults(results: results);
  }
}

/// Renders [results] (already grouped and ordered by `SearchBuilder`) as one
/// flat, lazily-built list with a header per group — a single `ListView` so
/// long result sets stay virtualized rather than nesting a list per group.
class _GroupedResults extends StatelessWidget {
  const _GroupedResults({required this.results});

  final List<SearchResult> results;

  @override
  Widget build(BuildContext context) {
    // Flatten to header/row slots once per build, so itemBuilder stays O(1).
    final slots = <Object>[];
    SearchResultGroup? current;
    for (final result in results) {
      if (result.group != current) {
        current = result.group;
        slots.add(current);
      }
      slots.add(result);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSizes.xxl),
      itemCount: slots.length,
      itemBuilder: (context, index) {
        final slot = slots[index];
        if (slot is SearchResultGroup) return _GroupHeader(group: slot, results: results);
        return _ResultTile(result: slot as SearchResult);
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.results});

  final SearchResultGroup group;
  final List<SearchResult> results;

  @override
  Widget build(BuildContext context) {
    final count = results.where((r) => r.group == group).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.lg, AppSizes.lg, AppSizes.sm),
      child: Row(
        children: [
          Text(
            group.label.toUpperCase(),
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.6),
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            '$count',
            style: context.textTheme.labelSmall?.copyWith(
              color: context.colors.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final routePath = result.routePath;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: context.colors.primary.withValues(alpha: 0.1),
        child: Icon(result.icon, size: AppSizes.iconSm, color: context.colors.primary),
      ),
      title: Text(result.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: result.kind == null && result.subtitle.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.kind != null) ...[
                  TransactionKindBadge(kind: result.kind!, compact: true),
                  if (result.subtitle.isNotEmpty) const SizedBox(height: 2),
                ],
                if (result.subtitle.isNotEmpty)
                  Text(result.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
      trailing: result.amount == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyFormatter.instance.formatCompact(result.amount!),
                  style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (result.date != null)
                  Text(
                    result.date!.shortDate,
                    style: context.textTheme.labelSmall?.copyWith(
                      color: context.colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
      onTap: routePath == null ? null : () => context.push(routePath),
    );
  }
}
