import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/filter/sms_sort_order.dart';
import '../../domain/sms_availability.dart';
import '../../domain/sms_import_status.dart';
import '../../domain/sms_inbox_item.dart';
import '../../domain/sms_transaction_direction.dart';
import '../providers/sms_inbox_providers.dart';
import '../sms_bulk_converter.dart';
import '../sms_conversion_router.dart';
import '../widgets/sms_active_filter_chips.dart';
import '../widgets/sms_bulk_convert_sheet.dart';
import '../widgets/sms_convert_sheet.dart';
import '../widgets/sms_duplicate_review_sheet.dart';
import '../widgets/sms_empty_state.dart';
import '../widgets/sms_inbox_skeleton_list.dart';
import '../widgets/sms_message_detail_sheet.dart';
import '../widgets/sms_message_tile.dart';
import '../widgets/sms_multi_select_toolbar.dart';
import '../widgets/sms_permission_gate_view.dart';
import '../widgets/sms_search_filter_bar.dart';

/// Pushed screen — "another History filter/tab" per the feature spec, but
/// with its own search/filter/permission/multi-select chrome, different
/// enough from the read-only unified History feed to warrant its own
/// screen rather than a body swap inside `TransactionsScreen`.
///
/// Laid out like a messaging app (Gmail / Google Messages) rather than a
/// dashboard: compact rows, a pinned search + filter header, and row
/// actions reached by swipe, tap, or long-press multi-select — so an inbox
/// of thousands of bank SMS stays reviewable with minimal scrolling.
class SmsInboxScreen extends ConsumerStatefulWidget {
  const SmsInboxScreen({super.key});

  /// Routed rather than pushed directly: an unqualified `Navigator.push` from
  /// a tab lands on that branch's navigator, i.e. inside the shell's body,
  /// which puts the shell's FAB and nav bar over this screen and over every
  /// sheet it opens. [AppRoutes.smsInbox] is top-level, so it covers the shell.
  static Future<void> show(BuildContext context) async {
    await context.push(AppRoutes.smsInbox);
  }

  @override
  ConsumerState<SmsInboxScreen> createState() => _SmsInboxScreenState();
}

class _SmsInboxScreenState extends ConsumerState<SmsInboxScreen> with WidgetsBindingObserver {
  final Set<String> _selectedIds = {};
  bool _hasAutoScanned = false;

  /// Guards the toolbar while a bulk conversion is mid-flight: a second tap
  /// would run the loop again over messages the first pass hasn't finished
  /// marking imported yet, creating duplicate transactions.
  bool _isBulkConverting = false;

  /// Guards a single item against being converted twice concurrently — a
  /// rapid double-trigger (double swipe, or opening convert from two entry
  /// points before the first finishes) would otherwise both reach `route()`
  /// and both create a transaction from the same SMS.
  final Set<String> _convertingIds = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The permission gate's own suggested recovery for "permanently denied"
  /// sends the user to system Settings to grant access there. Nothing else
  /// re-checks permission status on return, so without this the gate stays
  /// stuck showing "denied" even after the user actually granted it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(smsAvailabilityProvider.notifier).recheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    final availabilityAsync = ref.watch(smsAvailabilityProvider);

    ref.listen(smsAvailabilityProvider, (previous, next) {
      if (next.value == SmsAvailability.granted && !_hasAutoScanned) {
        _hasAutoScanned = true;
        ref.read(smsInboxItemsProvider.notifier).scan();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Inbox'),
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              tooltip: 'Sort',
              onPressed: () => _openSortMenu(context),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () => ref.read(smsInboxItemsProvider.notifier).scan(),
            ),
          ],
        ],
      ),
      body: availabilityAsync.when(
        loading: () => const SmsInboxSkeletonList(),
        error: (error, _) => Center(child: Text('Something went wrong: $error')),
        data: (availability) {
          if (availability != SmsAvailability.granted) {
            return SmsPermissionGateView(availability: availability);
          }
          if (!_hasAutoScanned) {
            _hasAutoScanned = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(smsInboxItemsProvider.notifier).scan();
            });
          }
          return _buildInboxBody(context);
        },
      ),
      bottomNavigationBar: !_selectionMode
          ? null
          : SmsMultiSelectToolbar(
              selectedCount: _selectedIds.length,
              onConvert: _isBulkConverting ? null : _handleConvertSelected,
              onIgnore: _handleIgnoreSelected,
              onDelete: _handleDeleteSelected,
              onSelectAll: _handleSelectAll,
              onCancel: () => setState(_selectedIds.clear),
            ),
    );
  }

  /// Sort lives beside the filter rather than inside its sheet: it reorders
  /// the feed instead of narrowing it, so it isn't something to Apply or
  /// Clear. Mirrors `TransactionsScreen`'s sort menu.
  Future<void> _openSortMenu(BuildContext context) async {
    final current = ref.read(smsFilterCriteriaProvider).sort;
    final selected = await showModalBottomSheet<SmsSortOrder>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final sort in SmsSortOrder.values)
              ListTile(
                title: Text(sort.label),
                trailing: sort == current ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.of(sheetContext).pop(sort),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;

    final notifier = ref.read(smsFilterCriteriaProvider.notifier);
    notifier.state = notifier.state.copyWith(sort: selected);
  }

  Widget _buildInboxBody(BuildContext context) {
    final itemsAsync = ref.watch(smsInboxItemsProvider);

    return itemsAsync.when(
      loading: () => const SmsInboxSkeletonList(),
      error: (error, _) => Center(child: Text('Something went wrong: $error')),
      data: (_) {
        final visible = ref.watch(smsFilteredItemsProvider);
        final rows = _buildRows(visible);

        return RefreshIndicator(
          onRefresh: () => ref.read(smsInboxItemsProvider.notifier).scan(),
          child: CustomScrollView(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _FilterHeaderDelegate(
                  hasActiveFilters: ref.watch(smsFilterCriteriaProvider).hasActiveFilters,
                ),
              ),
              if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SmsEmptyState(onRefresh: () => ref.read(smsInboxItemsProvider.notifier).scan()),
                )
              else
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) => _buildRow(rows[index]),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: AppSizes.xxl)),
            ],
          ),
        );
      },
    );
  }

  /// Flattens the date-grouped inbox into a single row list so the whole
  /// feed stays lazily built by [SliverList.builder] — grouping with nested
  /// `Column`s would build every row of every group up front, which is what
  /// makes a 3000-SMS inbox stutter.
  List<_Row> _buildRows(List<SmsInboxItem> items) {
    final grouped = groupBy(items, (SmsInboxItem item) => item.rawMessage.date.dateOnly);
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return [
      for (final date in sortedDates) ...[
        _Row.header(date, grouped[date]!),
        for (final item in grouped[date]!) _Row.item(item),
      ],
    ];
  }

  Widget _buildRow(_Row row) {
    final item = row.item;
    if (item == null) {
      return _SmsDateGroupHeader(date: row.date!, items: row.groupItems!);
    }

    return _swipeable(
      item,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SmsMessageTile(
            key: ValueKey(item.id),
            item: item,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(item.id),
            onTap: () => _selectionMode ? _toggleSelected(item.id) : _openDetail(item),
            onLongPress: () => setState(() => _selectedIds.add(item.id)),
          ),
          const Divider(height: 1, indent: 68),
        ],
      ),
    );
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  /// A flagged duplicate opens the review sheet instead of the normal detail
  /// sheet: the useful question about it isn't "what does this say" but "is
  /// this really a duplicate", which needs the original alongside it.
  Future<void> _openDetail(SmsInboxItem item) async {
    if (item.isDuplicate) {
      await _openDuplicateReview(item);
      return;
    }

    final action = await SmsMessageDetailSheet.show(context, item);
    if (action == null || !mounted) return;

    final notifier = ref.read(smsInboxItemsProvider.notifier);
    switch (action) {
      case SmsRowAction.convert:
        await _handleConvert(item);
      case SmsRowAction.ignore:
        await notifier.markIgnored(item.id);
      case SmsRowAction.restore:
        await notifier.restore(item.id);
      case SmsRowAction.delete:
        await notifier.deleteMany([item.id]);
    }
  }

  Future<void> _openDuplicateReview(SmsInboxItem item) async {
    final action = await SmsDuplicateReviewSheet.show(context, item);
    if (action == null || !mounted) return;

    final notifier = ref.read(smsInboxItemsProvider.notifier);
    switch (action) {
      case SmsDuplicateAction.delete:
        await notifier.deleteMany([item.id]);
      case SmsDuplicateAction.moveToInbox:
        await notifier.clearDuplicateFlag(item.id);
        if (mounted) _showSnack('Moved to your inbox.');
      case SmsDuplicateAction.convertAnyway:
        await _handleConvert(item);
      case SmsDuplicateAction.ignore:
        await notifier.markIgnored(item.id);
    }
  }

  /// Swipe right → open the convert sheet, swipe left → ignore — per the
  /// feature spec. Both directions call the same action the detail sheet's
  /// buttons trigger and always "un-dismiss" (return false): the row's
  /// visual state (status chip) updates via the normal provider-driven
  /// rebuild instead of a dismiss animation, since neither swipe should
  /// make the item vanish from an "All"-filtered list.
  Widget _swipeable(SmsInboxItem item, Widget child) {
    if (item.status != SmsImportStatus.pending || _selectionMode) return child;
    // A duplicate has no swipe-to-convert: converting one is the rare "really
    // charged twice" case, and it should only ever happen from the review
    // sheet where the original is on screen to judge it against — never from
    // a one-handed swipe that could just as easily be a mis-scroll.
    if (item.isDuplicate) return child;

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.horizontal,
      background: _swipeBackground(
        alignment: Alignment.centerLeft,
        icon: Icons.bolt_rounded,
        label: 'Convert',
        color: AppColors.success,
      ),
      secondaryBackground: _swipeBackground(
        alignment: Alignment.centerRight,
        icon: Icons.visibility_off_rounded,
        label: 'Ignore',
        color: AppColors.debit,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await _handleConvert(item);
        } else {
          await ref.read(smsInboxItemsProvider.notifier).markIgnored(item.id);
        }
        return false;
      },
      child: child,
    );
  }

  Widget _swipeBackground({
    required Alignment alignment,
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      alignment: alignment,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: AppSizes.iconMd),
          const SizedBox(width: AppSizes.xs),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _handleConvert(SmsInboxItem item) async {
    if (!_convertingIds.add(item.id)) return;
    try {
      final target = await SmsConvertSheet.show(context);
      if (target == null || !mounted) return;
      await ref.read(smsConversionRouterProvider).route(context, ref, item, target);
    } finally {
      _convertingIds.remove(item.id);
    }
  }

  void _handleSelectAll() {
    final visible = ref.read(smsFilteredItemsProvider);
    setState(() => _selectedIds.addAll(visible.map((item) => item.id)));
  }

  /// One selection opens the full convert sheet (all 11 targets); several
  /// open the bulk sheet, which trades that breadth for entering the shared
  /// answers once. See `SmsBulkConverter` for why bulk covers only
  /// Expense/Income.
  Future<void> _handleConvertSelected() async {
    final all = ref.read(smsInboxItemsProvider).value ?? const [];
    final selected = all.where((item) => _selectedIds.contains(item.id)).toList();
    setState(_selectedIds.clear);
    if (selected.isEmpty) return;

    if (selected.length == 1) {
      await _handleConvert(selected.single);
      return;
    }
    await _handleBulkConvert(selected);
  }

  Future<void> _handleBulkConvert(List<SmsInboxItem> selected) async {
    // Two exclusions, both load-bearing:
    //  - already-imported messages, or a selection that swept one up would
    //    create a second transaction for the same payment;
    //  - flagged duplicates, which are only ever convertible one at a time
    //    from the review sheet where the original is visible. Select-all
    //    inside the Duplicates filter would otherwise bulk-convert the very
    //    messages this feature exists to hold back.
    final convertible = selected
        .where((item) => item.status != SmsImportStatus.imported && !item.isDuplicate)
        .toList();

    if (convertible.isEmpty) {
      _showSnack(
        selected.any((item) => item.isDuplicate)
            ? 'Open a duplicate to review it before converting.'
            : 'Those messages are already converted.',
      );
      return;
    }

    final config = await SmsBulkConvertSheet.show(context, convertible);
    if (config == null || !mounted) return;

    setState(() => _isBulkConverting = true);
    final result = await ref.read(smsBulkConverterProvider).convert(convertible, config);

    // Reloaded once here rather than per message inside the loop — that's
    // what keeps a 500-message convert from doing 500 full reloads.
    if (result.converted > 0) {
      await ref.read(smsInboxItemsProvider.notifier).refresh();
      ref.invalidate(merchantMemoriesProvider);
    }
    if (!mounted) return;
    setState(() => _isBulkConverting = false);

    _showSnack(_bulkResultMessage(result));
  }

  /// Reports what actually happened, including partial failures — a blanket
  /// "Done" would hide messages that silently stayed pending.
  String _bulkResultMessage(SmsBulkConvertResult result) {
    final parts = [
      if (result.converted > 0) 'Converted ${result.converted}',
      if (result.skipped > 0) 'skipped ${result.skipped} with no amount',
      if (result.failed > 0) "couldn't convert ${result.failed}",
    ];
    if (parts.isEmpty) return 'Nothing to convert.';
    return '${parts.join(' • ')}.';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleIgnoreSelected() async {
    final ids = List<String>.from(_selectedIds);
    setState(_selectedIds.clear);
    await ref.read(smsInboxItemsProvider.notifier).markIgnoredMany(ids);
  }

  Future<void> _handleDeleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    setState(_selectedIds.clear);
    await ref.read(smsInboxItemsProvider.notifier).deleteMany(ids);
  }
}

/// One entry in the flattened feed — either a date header or an SMS row.
class _Row {
  const _Row.item(this.item)
      : date = null,
        groupItems = null;
  const _Row.header(this.date, this.groupItems) : item = null;

  final SmsInboxItem? item;
  final DateTime? date;
  final List<SmsInboxItem>? groupItems;
}

/// Keeps search + filter chips reachable while scrolling a long inbox.
class _FilterHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _FilterHeaderDelegate({required this.hasActiveFilters});

  /// Drives the extent: the chips row only exists when a filter is on, and a
  /// sliver header may not claim more extent than its child paints.
  final bool hasActiveFilters;

  /// Summed from the children's own declared heights rather than a literal,
  /// so the two can't drift apart the way they did when this was hardcoded.
  double get _extent => SmsSearchFilterBar.height + (hasActiveFilters ? SmsActiveFilterChips.height : 0);

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Material(
      color: context.colors.surface,
      elevation: overlapsContent || shrinkOffset > 0 ? 1 : 0,
      child: const SizedBox.expand(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [SmsSearchFilterBar(), SmsActiveFilterChips()],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_FilterHeaderDelegate oldDelegate) => oldDelegate.hasActiveFilters != hasActiveFilters;
}

class _SmsDateGroupHeader extends StatelessWidget {
  const _SmsDateGroupHeader({required this.date, required this.items});

  final DateTime date;
  final List<SmsInboxItem> items;

  @override
  Widget build(BuildContext context) {
    final netTotal = items.fold<double>(0.0, (total, item) {
      final parsed = item.parsed;
      if (parsed == null) return total;
      return total + (parsed.direction == SmsTransactionDirection.credit ? parsed.amount : -parsed.amount);
    });

    return Container(
      color: context.colors.surfaceContainerHighest.withValues(alpha: 0.4),
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(date.sectionLabel, style: context.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text(
            '${netTotal >= 0 ? '+' : '-'}${CurrencyFormatter.instance.format(netTotal.abs())}',
            style: context.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: netTotal >= 0 ? AppColors.credit : AppColors.debit,
            ),
          ),
        ],
      ),
    );
  }
}
