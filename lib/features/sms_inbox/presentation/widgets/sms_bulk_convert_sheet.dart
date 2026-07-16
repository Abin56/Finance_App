import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/bank_avatar.dart';
import '../../../../shared/widgets/buttons/primary_button.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../domain/merchant/merchant_key.dart';
import '../../domain/sms_inbox_item.dart';
import '../../domain/sms_transaction_direction.dart';
import '../providers/sms_inbox_providers.dart';
import '../sms_bulk_converter.dart';

/// Collects the answers shared by every selected SMS — type, category,
/// payment method, notes — exactly once, then hands them back as an
/// [SmsBulkConvertConfig]. The actual creation loop is
/// [SmsBulkConverter]'s job; this sheet only gathers input and never writes.
///
/// Only offered for Expense and Income; see [SmsBulkConverter] for why the
/// other targets stay single-convert.
class SmsBulkConvertSheet extends ConsumerStatefulWidget {
  const SmsBulkConvertSheet._({required this.items});

  final List<SmsInboxItem> items;

  static Future<SmsBulkConvertConfig?> show(BuildContext context, List<SmsInboxItem> items) {
    return showModalBottomSheet<SmsBulkConvertConfig>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SmsBulkConvertSheet._(items: items),
    );
  }

  @override
  ConsumerState<SmsBulkConvertSheet> createState() => _SmsBulkConvertSheetState();
}

class _SmsBulkConvertSheetState extends ConsumerState<SmsBulkConvertSheet> {
  late TransactionType _type = _dominantType();
  final _notesController = TextEditingController();
  String? _categoryId;
  String? _accountId;
  bool _categoryTouched = false;
  String? _categoryError;
  String? _accountError;

  /// Starts on the side of the ledger most of the selection is already on, so
  /// the common "10 salary SMS" case opens on Income without a tap. Only a
  /// default — the user can flip it.
  TransactionType _dominantType() {
    final credits = widget.items
        .where((item) => item.parsed?.direction == SmsTransactionDirection.credit)
        .length;
    return credits > widget.items.length / 2 ? TransactionType.income : TransactionType.expense;
  }

  /// The messages whose direction contradicts the chosen [_type]. Surfaced as
  /// a warning rather than blocked: the user may genuinely be right (a refund
  /// filed as income), but converting a credit into an expense silently would
  /// put a wrong sign into their real balances.
  int get _conflictingCount {
    final expected = _type == TransactionType.income
        ? SmsTransactionDirection.credit
        : SmsTransactionDirection.debit;
    return widget.items
        .where((item) => item.parsed?.direction != null && item.parsed!.direction != expected)
        .length;
  }

  /// Messages with no parsed amount can't become a transaction — see
  /// [SmsBulkConverter]. Counted up front so the user knows before they
  /// commit, not after.
  int get _unusableCount => widget.items.where((item) => (item.parsed?.amount ?? 0) <= 0).length;

  double get _totalAmount =>
      widget.items.fold(0.0, (sum, item) => sum + (item.parsed?.amount ?? 0));

  /// How many will actually be created — the count the button promises.
  int get _convertibleCount => widget.items.length - _unusableCount;

  static String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

  /// Suggests a category only when every selected message is from the *same*
  /// merchant — that's the "15 Amazon purchases" case, where one suggestion
  /// is genuinely right for all of them. A mixed selection gets no
  /// suggestion, because any single category would be wrong for most of it.
  String? _suggestedCategoryId() {
    final keys = widget.items.map((item) => MerchantKey.normalize(item.parsed?.merchantOrSender)).toSet();
    if (keys.length != 1 || keys.first == null) return null;

    return ref
        .read(merchantCategorySuggesterProvider)
        .suggest(
          merchant: widget.items.first.parsed?.merchantOrSender,
          transactionType: _type,
          categories: ref.read(categoriesForTypeProvider(_type)),
          smsCategory: widget.items.first.parsed?.category,
        )
        ?.categoryId;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() {
      _categoryError = _categoryId == null ? 'Select a category' : null;
      _accountError = _accountId == null ? 'Select a payment method' : null;
    });
    if (_categoryId == null || _accountId == null) return;

    Navigator.of(context).pop(
      SmsBulkConvertConfig(
        type: _type,
        categoryId: _categoryId!,
        accountId: _accountId!,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesForTypeProvider(_type));
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];

    // Seeded here rather than in a field initializer because the suggestion
    // depends on the chosen type, which the user can change. Only ever fills
    // an untouched picker, so it can't overwrite a real choice.
    if (!_categoryTouched && _categoryId == null) {
      _categoryId = _suggestedCategoryId();
    }
    // A category from the previous type won't exist in this type's list.
    if (_categoryId != null && !categories.any((category) => category.id == _categoryId)) {
      _categoryId = null;
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSizes.lg,
          right: AppSizes.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSizes.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Convert ${_plural(widget.items.length, 'message')}', style: context.textTheme.titleMedium),
              const SizedBox(height: AppSizes.xs),
              Text(
                'Each message becomes its own transaction. Total ${CurrencyFormatter.instance.format(_totalAmount)}.',
                style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSizes.md),

              SegmentedButton<TransactionType>(
                segments: const [
                  ButtonSegment(value: TransactionType.expense, label: Text('Expense'), icon: Icon(Icons.arrow_upward_rounded)),
                  ButtonSegment(value: TransactionType.income, label: Text('Income'), icon: Icon(Icons.arrow_downward_rounded)),
                ],
                selected: {_type},
                onSelectionChanged: (selection) => setState(() {
                  _type = selection.first;
                  _categoryTouched = false;
                  _categoryId = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),

              _Label(text: 'Category'),
              DropdownButtonFormField<String>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(errorText: _categoryError, isDense: true),
                hint: const Text('Select a category'),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _categoryId = value;
                  _categoryTouched = true;
                  _categoryError = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),

              _Label(text: 'Payment method'),
              DropdownButtonFormField<String>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: InputDecoration(errorText: _accountError, isDense: true),
                hint: const Text('Select a payment method'),
                items: [
                  for (final account in accounts)
                    DropdownMenuItem(
                      value: account.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BankAvatar(bankId: account.bankId, fallbackName: account.name, size: 20),
                          const SizedBox(width: AppSizes.sm),
                          Flexible(child: Text(account.name, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _accountId = value;
                  _accountError = null;
                }),
              ),
              const SizedBox(height: AppSizes.md),

              _Label(text: 'Notes (optional)'),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(isDense: true, hintText: 'Applied to every transaction'),
                textInputAction: TextInputAction.done,
              ),

              if (_conflictingCount > 0)
                _Warning(
                  text: '$_conflictingCount of these look like '
                      '${_type == TransactionType.income ? 'money going out' : 'money coming in'}. '
                      'They will still be created as ${_type.label.toLowerCase()}.',
                ),
              if (_unusableCount > 0)
                _Warning(
                  text: '${_plural(_unusableCount, 'message')} have no readable amount and will be '
                      'skipped, staying in your inbox to convert manually.',
                ),

              const SizedBox(height: AppSizes.lg),
              // Names the outcome rather than repeating the title: what the
              // user is about to create is the thing worth confirming.
              PrimaryButton(
                label: 'Create ${_plural(_convertibleCount, 'transaction')}',
                onPressed: _convertibleCount > 0 ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Text(text, style: context.textTheme.titleSmall),
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: AppSizes.iconSm, color: AppColors.pending),
          const SizedBox(width: AppSizes.xs),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
