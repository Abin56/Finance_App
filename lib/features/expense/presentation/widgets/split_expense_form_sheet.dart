import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/presentation/providers/payment_schedule_providers.dart';
import '../../../../core/utils/account_display_name.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/validators.dart';
import '../../../../shared/widgets/bank_logo.dart';
import '../../../../shared/widgets/cards/app_card.dart';
import '../../../../shared/widgets/dialogs/delete_confirmation_dialog.dart';
import '../../../../shared/widgets/dialogs/sectioned_form_sheet.dart';
import '../../../../shared/widgets/inputs/month_year_stepper.dart';
import '../../../../shared/widgets/section_label.dart';
import '../../../accounts/presentation/providers/account_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../credit_cards/presentation/providers/credit_card_providers.dart';
import '../../../people/domain/person.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../../people/presentation/widgets/person_form_sheet.dart';
import '../../../sms_inbox/domain/sms_prefill.dart';
import '../../../sms_inbox/presentation/sms_import_completion.dart';
import '../../../transactions/domain/transaction_type.dart';
import '../../data/expense_repository.dart';
import '../../domain/expense.dart';
import '../../domain/expense_participant.dart';
import '../../domain/mixed_split.dart';
import '../../domain/split_type.dart';
import '../providers/expense_providers.dart';

/// The fields [SplitExpenseFormSheet] pre-fills and locks when converting an
/// existing plain expense into a split one — deliberately not an [Expense]
/// itself, since a plain transaction converted via Task 1's flow may not
/// have an `Expense` document at all (see `ExpenseRepository.convertToSplit`'s
/// `existingExpense` parameter).
class ConvertToSplitPrefill {
  const ConvertToSplitPrefill({
    required this.transactionId,
    required this.description,
    required this.totalAmount,
    required this.date,
    required this.categoryId,
    required this.accountId,
    required this.notes,
  });

  final String transactionId;
  final String description;
  final double totalAmount;
  final DateTime date;
  final String categoryId;
  final String accountId;
  final String notes;
}

/// Carries an in-progress, never-saved [AddExpenseScreen] form over into this
/// sheet when the user switches from a plain expense to a shared one — every
/// field here is a normal, fully editable initial value (same contract as
/// [SmsPrefill]), unlike [ConvertToSplitPrefill] which locks fields because a
/// real [Transaction] already exists behind them.
class AddExpenseDraftPrefill {
  const AddExpenseDraftPrefill({
    this.amount,
    this.description,
    this.categoryId,
    this.accountId,
    this.date,
    this.notes,
    this.excludeFromCalculations = false,
    this.accountingMonth,
  });

  final double? amount;
  final String? description;
  final String? categoryId;
  final String? accountId;
  final DateTime? date;
  final String? notes;
  final bool excludeFromCalculations;

  /// Non-null only when the source form had "Count this in a different
  /// month?" switched on — same meaning as [Transaction.accountingMonth].
  final DateTime? accountingMonth;
}

/// One participant row's editable state — either an existing [Person]
/// (picked by id) or a free-text name (no personId, not tracked as a
/// person). [valueController] holds the custom amount / percentage input;
/// unused (and ignored) for [SplitType.equal].
class _ParticipantRow {
  _ParticipantRow({String initialName = ''}) {
    nameController.text = initialName;
  }

  String? personId;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController valueController = TextEditingController();

  /// [SplitType.custom] only: false = auto — this row shares whatever's left
  /// of the total equally with the other unlocked rows; true = pinned to
  /// [valueController]'s typed amount. Also used for [_meRow], since Me is
  /// just another [_ParticipantRow] under the hood.
  bool locked = false;

  /// Stable identity for matching this row's resolved share back from
  /// [resolveMixedSplit] — a tracked person's id, or the typed name.
  String get mixedKey => personId ?? 'name:${nameController.text.trim()}';

  void dispose() {
    nameController.dispose();
    valueController.dispose();
  }
}

/// Bottom sheet for creating a split expense: description, amount, date,
/// category, account, a split-type selector, and an unlimited participant
/// list. For Custom/Percentage splits, a live "remaining to assign" banner
/// re-validates via [ExpenseRepository.resolveShares] on every keystroke so
/// the user always knows exactly what's left to assign, in plain language.
///
/// When [convertFrom] is supplied (Task 1's "convert an old expense" flow),
/// the description/amount/date/category/account/notes fields are pre-filled
/// from that transaction's own values and locked read-only — the user only
/// picks participants — and saving calls
/// [ExpenseRepository.convertToSplit] instead of `createExpense`, so no
/// second `Transaction` is ever created for the same spend. [existingExpense]
/// is only non-null when an `Expense` document already exists for that
/// transaction (should not normally happen for a convert-eligible plain
/// transaction, but handled so this widget never assumes either way).
class SplitExpenseFormSheet extends ConsumerStatefulWidget {
  const SplitExpenseFormSheet({
    super.key,
    this.convertFrom,
    this.existingExpense,
    this.assignOnly = false,
    this.editing,
    this.smsPrefill,
    this.initialParticipant,
    this.draft,
  });

  final ConvertToSplitPrefill? convertFrom;
  final Expense? existingExpense;

  /// Set when opened from the SMS Inbox's "Split Expense" option. Unlike
  /// [convertFrom] (which assumes a `Transaction` already exists and routes
  /// through `convertToSplit`, which deliberately never creates a new one),
  /// an SMS has never created any `Transaction` — so this seeds the same
  /// brand-new-creation fields the plain "Share an expense" flow already
  /// renders (editable, not locked) and still saves via `createExpense`.
  /// Mutually exclusive with [convertFrom]/[editing].
  final SmsPrefill? smsPrefill;

  /// Part 1's "Assign to Person" entry point — always implies [convertFrom]
  /// is set (assigning only makes sense for an existing transaction). Locks
  /// the split-type to a single person + "Me", hides the Equal/Custom/
  /// Percentage picker (an assignment isn't a multi-way split), and saves
  /// via [ExpenseRepository.convertToAssigned] instead of `convertToSplit`.
  final bool assignOnly;

  /// Milestone 17's "edit an already-split/assigned expense" entry point —
  /// mutually exclusive with [convertFrom]. Every field prefills from this
  /// [Expense] and stays editable (unlike [convertFrom], which locks the
  /// original transaction's fields read-only), and saving calls
  /// [ExpenseRepository.editExpense] instead of `convertToSplit`/
  /// `convertToAssigned`/`createExpense`.
  final Expense? editing;

  /// Set when opened from that person's own Contact Ledger screen — seeds
  /// the first "share with" row with this person instead of a blank row, so
  /// the user isn't asked to pick again who they already navigated to. Still
  /// editable/removable like any other row (a shared expense can include
  /// more people than just this one).
  final Person? initialParticipant;

  /// Set when opened from [AddExpenseScreen]'s "Share Expense" row — carries
  /// over everything the user already typed there so switching to a shared
  /// expense never re-asks for the same information. Mutually exclusive with
  /// [convertFrom]/[editing]/[smsPrefill] (a brand-new-creation-only prefill).
  final AddExpenseDraftPrefill? draft;

  /// Resolves to `true` only when the expense was saved, so callers show a
  /// success confirmation only on an actual save (not on cancel/back).
  static Future<bool?> show(
    BuildContext context, {
    ConvertToSplitPrefill? convertFrom,
    Expense? existingExpense,
    bool assignOnly = false,
    Expense? editing,
    SmsPrefill? smsPrefill,
    Person? initialParticipant,
    AddExpenseDraftPrefill? draft,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      useSafeArea: true,
      builder: (_) => SplitExpenseFormSheet(
        convertFrom: convertFrom,
        existingExpense: existingExpense,
        assignOnly: assignOnly,
        editing: editing,
        smsPrefill: smsPrefill,
        initialParticipant: initialParticipant,
        draft: draft,
      ),
    );
  }

  @override
  ConsumerState<SplitExpenseFormSheet> createState() => _SplitExpenseFormSheetState();
}

class _SplitExpenseFormSheetState extends ConsumerState<SplitExpenseFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _descriptionController = TextEditingController(
    text: widget.editing?.description ??
        widget.convertFrom?.description ??
        widget.smsPrefill?.merchantOrSender ??
        widget.draft?.description ??
        '',
  );
  late final _amountController = TextEditingController(
    text: widget.editing != null
        ? widget.editing!.totalAmount.toStringAsFixed(2)
        : widget.convertFrom != null
            ? widget.convertFrom!.totalAmount.toStringAsFixed(2)
            : widget.smsPrefill != null
                ? widget.smsPrefill!.amount.toStringAsFixed(2)
                : (widget.draft?.amount == null ? '' : widget.draft!.amount!.toStringAsFixed(2)),
  );
  late final _notesController = TextEditingController(
    text: widget.editing?.notes ?? widget.convertFrom?.notes ?? widget.smsPrefill?.note ?? widget.draft?.notes ?? '',
  );
  final _amountFocusNode = FocusNode();
  late DateTime _date =
      widget.editing?.date ?? widget.convertFrom?.date ?? widget.smsPrefill?.dateTime ?? widget.draft?.date ?? DateTime.now();

  /// Null while editing means "leave every current installment's due date
  /// alone" (see `ExpenseRepository.editExpense`'s `dueDate` param) — only
  /// set once the user actively picks a new one via [_pickDueDate]. For a
  /// brand-new schedule (create/convert), always non-null so a real due
  /// date — not the expense's own date — is threaded through from the start.
  late DateTime? _dueDate = widget.editing == null ? _date.add(const Duration(days: 7)) : null;
  late String? _accountId = widget.editing?.accountId ??
      widget.convertFrom?.accountId ??
      widget.smsPrefill?.suggestedAccountId ??
      widget.draft?.accountId;
  late String? _categoryId = widget.editing?.categoryId ??
      widget.convertFrom?.categoryId ??
      widget.smsPrefill?.suggestedCategoryId ??
      widget.draft?.categoryId;
  String? _accountError;
  String? _categoryError;

  /// Mirrors the same-named switch on [AddExpenseScreen] — only meaningful
  /// on the plain-create path (editing/converting already have a real
  /// [Transaction] with its own values, which this sheet never touches).
  late bool _excludeFromCalculations = widget.draft?.excludeFromCalculations ?? false;
  late bool _customAccountingMonth = widget.draft?.accountingMonth != null;
  late DateTime _accountingMonth = widget.draft?.accountingMonth ?? DateTime(_date.year, _date.month);

  /// Assigning is always a 2-way custom split (Me + one person) — never
  /// Equal/Percentage, since there's no "how to share" choice to make.
  late SplitType _splitType = widget.editing?.splitType ?? (widget.assignOnly ? SplitType.custom : SplitType.equal);

  /// Whether "Me" participates in this expense at all — Milestone 14 Task 1
  /// replaced the old mandatory/locked "Me" row with this checkbox, checked
  /// by default. [_meRow] only holds Me's adjustable Custom/Percentage share
  /// controller; it's synthesized into the saved participant list by
  /// [_buildInputs] only when [_includeMe] is true, and never rendered as a
  /// row in [_participants] (kept structurally separate so "how many other
  /// people am I sharing with" and "do I participate" are independent
  /// questions the UI never conflates).
  late bool _includeMe = widget.editing == null || widget.editing!.meParticipant != null;

  /// A re-opened [SplitType.custom] expense had every amount hand-typed, so every row
  /// starts locked in the mixed manual/auto engine — otherwise it would treat them all
  /// as auto and silently flatten a previously uneven split down to equal shares the
  /// moment this sheet opens. A re-opened equal split is genuinely all-equal, so auto
  /// (unlocked) is correct there — see [_resolveMixed].
  bool get _reopenedAsLocked => widget.editing?.splitType == SplitType.custom;

  late final _meRow = _ParticipantRow(initialName: 'Me')
    ..valueController.text = widget.editing?.meParticipant?.share.toStringAsFixed(2) ?? ''
    ..locked = _reopenedAsLocked;

  /// The dynamic "share with" rows — ordinary participants only, Me is
  /// tracked separately via [_includeMe]/[_meRow]. [assignOnly] starts (and
  /// stays locked to) exactly one row — no add/remove. When [SplitExpenseFormSheet.editing]
  /// is set, prefilled from that expense's non-"Me" participants instead of
  /// a single blank row.
  late final List<_ParticipantRow> _participants = widget.editing == null
      ? [
          if (widget.initialParticipant != null)
            _ParticipantRow(initialName: widget.initialParticipant!.name)..personId = widget.initialParticipant!.id
          else
            _ParticipantRow(),
        ]
      : [
          for (final p in widget.editing!.participants.where((p) => !p.isMe))
            _ParticipantRow(initialName: p.name)
              ..personId = p.personId
              ..valueController.text = p.share.toStringAsFixed(2)
              ..locked = _reopenedAsLocked,
        ];
  bool _isSaving = false;
  String? _splitError;
  String? _personError;

  /// The live-resolved shares for the current form state — drives the
  /// "before you save" preview (Your Spending / Money You'll Get Back).
  /// Null whenever the amount/shares aren't valid yet.
  List<ExpenseParticipant>? _preview;

  bool get _isConverting => widget.convertFrom != null;
  bool get _isEditing => widget.editing != null;

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    _amountFocusNode.dispose();
    _meRow.dispose();
    for (final row in _participants) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Prefilled forms (editing/converting) should show the live preview right
    // away, not only after the first keystroke.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revalidateSplit();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _pickDueDate(DateTime currentDueDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentDueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  void _addParticipant() {
    setState(() {
      _participants.add(_ParticipantRow());
      _revalidateSplit();
    });
  }

  /// Opens [PersonFormSheet] to create a new person without leaving this
  /// sheet — Task 1's "make add-new-person one tap" ask. Doesn't attempt to
  /// auto-select the newly created person (the sheet doesn't return one);
  /// the person simply appears in the row's dropdown immediately after,
  /// avoiding a fragile "guess which person was just created" heuristic.
  Future<void> _createNewPerson() => PersonFormSheet.show(context);

  void _removeParticipant(int index) {
    setState(() {
      _participants.removeAt(index).dispose();
      _revalidateSplit();
    });
  }

  /// Every row currently participating — Me (if included) first, then any
  /// participant row with a non-blank name. Shared by [_buildInputs],
  /// [_resolveMixed], and the "Custom" mode UI (toggle buttons, live banner).
  List<_ParticipantRow> get _includedRows => [
        if (_includeMe) _meRow,
        for (final row in _participants)
          if (row.nameController.text.trim().isNotEmpty) row,
      ];

  /// [SplitType.custom] only: locked rows keep their typed amount, unlocked
  /// rows auto-share whatever's left of [total] equally — see
  /// [resolveMixedSplit]. Null for every other split type, or once there's
  /// nobody to split between.
  MixedSplitResult? _resolveMixed(double total) {
    if (_splitType != SplitType.custom) return null;
    final rows = _includedRows;
    if (rows.isEmpty) return null;
    return resolveMixedSplit(total, [
      for (final row in rows)
        MixedParticipantInput(
          key: row.mixedKey,
          locked: row.locked,
          value: double.tryParse(row.valueController.text.trim()) ?? 0,
        ),
    ]);
  }

  List<ExpenseParticipantInput> _buildInputs() {
    if (_splitType == SplitType.custom) {
      final total = double.tryParse(_amountController.text.trim()) ?? 0;
      final mixed = _resolveMixed(total);
      // Once the mixed split resolves cleanly, every row already has a concrete final
      // amount (locked or auto) — feed those straight through so the exact-sum check
      // inside `ExpenseRepository.resolveShares` always passes trivially. Mid-error
      // (e.g. manual amounts already exceed the total), fall back to the raw typed
      // values so the repository's own validation still catches it at save time.
      return [
        for (final row in _includedRows)
          ExpenseParticipantInput(
            personId: row.personId,
            name: row == _meRow ? 'Me' : row.nameController.text.trim(),
            isMe: row == _meRow,
            value: mixed?.error == null
                ? mixed?.shares.firstWhereOrNull((s) => s.key == row.mixedKey)?.share
                : double.tryParse(row.valueController.text.trim()),
          ),
      ];
    }
    return [
      if (_includeMe)
        ExpenseParticipantInput(
          name: 'Me',
          isMe: true,
          value: double.tryParse(_meRow.valueController.text.trim()),
        ),
      for (final row in _participants)
        if (row.nameController.text.trim().isNotEmpty)
          ExpenseParticipantInput(
            personId: row.personId,
            name: row.nameController.text.trim(),
            value: double.tryParse(row.valueController.text.trim()),
          ),
    ];
  }

  /// Re-runs [ExpenseRepository.resolveShares] against the current form
  /// state so the "remaining to assign" banner always reflects live input —
  /// surfaces the exact `AppException` message on mismatch, clears it on
  /// success (or once the total amount isn't a valid number yet).
  void _revalidateSplit() {
    final total = double.tryParse(_amountController.text.trim());
    if (total == null || total <= 0) {
      setState(() {
        _splitError = null;
        _preview = null;
      });
      return;
    }
    if (_splitType == SplitType.custom) {
      final mixed = _resolveMixed(total);
      if (mixed == null) {
        setState(() {
          _splitError = null;
          _preview = null;
        });
        return;
      }
      if (mixed.error != null) {
        setState(() {
          _splitError = mixed.error;
          _preview = null;
        });
        return;
      }
      // Every unlocked row's field always shows its live auto-computed share (not just
      // internal state) — setting `.text` doesn't fire `onChanged`, so this can't loop.
      for (final row in _includedRows) {
        if (row.locked) continue;
        final share = mixed.shares.firstWhereOrNull((s) => s.key == row.mixedKey)?.share;
        if (share != null) row.valueController.text = share.toStringAsFixed(2);
      }
    }
    final inputs = _buildInputs();
    if (inputs.isEmpty) {
      setState(() {
        _splitError = null;
        _preview = null;
      });
      return;
    }
    try {
      final resolved = ExpenseRepository.resolveShares(type: _splitType, total: total, inputs: inputs);
      setState(() {
        _splitError = null;
        _preview = resolved;
      });
    } on AppException catch (e) {
      setState(() {
        _splitError = e.message;
        _preview = null;
      });
    }
  }

  Future<void> _save() async {
    final formValid = _formKey.currentState!.validate();
    final assignedPersonId = widget.assignOnly ? _participants[0].personId : null;
    setState(() {
      _accountError = _accountId == null ? 'Select an account' : null;
      _categoryError = _categoryId == null ? 'Select a category' : null;
      _personError = widget.assignOnly && assignedPersonId == null ? 'Select a person' : null;
    });
    if (!formValid || _accountId == null || _categoryId == null) return;
    if (widget.assignOnly && assignedPersonId == null) return;

    setState(() => _isSaving = true);
    try {
      final repository = ref.read(expenseRepositoryProvider);
      final editing = widget.editing;
      final convertFrom = widget.convertFrom;
      if (editing != null) {
        final scheduleId = editing.scheduleId;
        final currentInstallments = scheduleId == null
            ? const <Installment>[]
            : ref.read(installmentsStreamProvider(scheduleId)).value ?? const <Installment>[];
        await repository.editExpense(
          expense: editing,
          currentInstallments: currentInstallments,
          description: _descriptionController.text.trim(),
          totalAmount: double.parse(_amountController.text.trim()),
          date: _date,
          categoryId: _categoryId!,
          accountId: _accountId!,
          notes: _notesController.text.trim(),
          splitType: _splitType,
          participantInputs: _buildInputs(),
          dueDate: _dueDate,
        );
      } else if (convertFrom != null && widget.assignOnly) {
        final person = _participants[0];
        // Me's remainder only applies when Me is included; otherwise the
        // person owes the full amount (no `partialAmount` = full assign).
        final partialAmount =
            _includeMe ? double.tryParse(person.valueController.text.trim()) : null;
        await repository.convertToAssigned(
          existingExpense: widget.existingExpense,
          transactionId: convertFrom.transactionId,
          description: convertFrom.description,
          totalAmount: convertFrom.totalAmount,
          date: convertFrom.date,
          categoryId: convertFrom.categoryId,
          accountId: convertFrom.accountId,
          notes: convertFrom.notes,
          personId: person.personId!,
          personName: person.nameController.text.trim(),
          partialAmount: partialAmount,
          dueDate: _dueDate,
        );
      } else if (convertFrom != null) {
        await repository.convertToSplit(
          existingExpense: widget.existingExpense,
          transactionId: convertFrom.transactionId,
          description: convertFrom.description,
          totalAmount: convertFrom.totalAmount,
          date: convertFrom.date,
          categoryId: convertFrom.categoryId,
          accountId: convertFrom.accountId,
          notes: convertFrom.notes,
          splitType: _splitType,
          participantInputs: _buildInputs(),
          dueDate: _dueDate,
        );
      } else {
        final expense = await repository.createExpense(
          description: _descriptionController.text.trim(),
          totalAmount: double.parse(_amountController.text.trim()),
          date: _date,
          categoryId: _categoryId!,
          accountId: _accountId!,
          splitType: _splitType,
          participantInputs: _buildInputs(),
          notes: _notesController.text.trim(),
          dueDate: _dueDate,
          excludeFromCalculations: _excludeFromCalculations,
          accountingMonth: _customAccountingMonth ? _accountingMonth : null,
          source: widget.smsPrefill == null ? null : 'sms',
        );

        await completeSmsImport(ref, smsPrefill: widget.smsPrefill, linkedEntityId: expense.transactionId);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save expense: $e')),
        );
      }
    }
  }

  /// Figma's "Delete Expense" button embedded in the edit form itself —
  /// same cascade-delete + confirm dialog as the Expense Details Actions
  /// list, just reachable without leaving this form first.
  Future<void> _deleteExpense() async {
    final expense = widget.editing;
    if (expense == null) return;
    final confirmed = await confirmDelete(context, entityName: 'Expense');
    if (!confirmed || !mounted) return;

    try {
      await ref.read(expenseRepositoryProvider).deleteExpense(expense);
      if (mounted) Navigator.of(context).pop(false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete expense: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsStreamProvider);
    final creditCards = ref.watch(creditCardsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesForTypeProvider(TransactionType.expense));
    final peopleAsync = ref.watch(peopleStreamProvider);
    final people = peopleAsync.value ?? const [];

    return Form(
      key: _formKey,
      child: SectionedFormSheet(
        title: _isEditing
            ? (widget.assignOnly ? 'Edit assigned expense' : 'Edit shared expense')
            : widget.assignOnly
                ? 'Assign to a person'
                : (_isConverting ? 'Turn into a shared expense' : 'Share an expense'),
        description: !_isConverting
            ? null
            : widget.assignOnly
                ? 'The amount, category, account, and date stay the same as the original expense — just choose who it was really for.'
                : 'The amount, category, account, and date stay the same as the original expense — just add who you shared it with.',
        confirmLabel: _isEditing
            ? 'Save changes'
            : widget.assignOnly
                ? 'Assign to person'
                : (_isConverting ? 'Turn into a shared expense' : 'Save shared expense'),
        isSaving: _isSaving,
        onConfirm: _save,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
              const SectionLabel('Expense Details'),
              const SizedBox(height: AppSizes.sm),
              if (_isConverting)
                _ReadOnlyExpenseSummary(prefill: widget.convertFrom!)
              else ...[
                TextFormField(
                  controller: _descriptionController,
                  decoration: _premiumDecoration(context, label: 'Description'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  validator: Validators.required,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _amountFocusNode.requestFocus(),
                ),
                const SizedBox(height: AppSizes.sm),
                TextFormField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  decoration: _premiumDecoration(context, label: 'Total amount'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: Validators.amount,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => _revalidateSplit(),
                ),
                const SizedBox(height: AppSizes.sm),
                accountsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, _) => Text('Could not load accounts: $error'),
                  data: (accounts) {
                    final validId = accounts.any((a) => a.id == _accountId) ? _accountId : null;
                    return DropdownButtonFormField<String>(
                      initialValue: validId,
                      decoration: _premiumDecoration(context, label: 'Account', errorText: _accountError),
                      style: Theme.of(context).textTheme.bodyMedium,
                      items: [
                        for (final account in accounts)
                          DropdownMenuItem(
                            value: account.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                BankLogo(bankId: account.bankId, fallbackName: account.name, size: 20),
                                const SizedBox(width: AppSizes.sm),
                                Flexible(
                                  child: Text(
                                    accountPickerLabel(account, creditCards),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() {
                        _accountId = value;
                        _accountError = null;
                      }),
                    );
                  },
                ),
                const SizedBox(height: AppSizes.sm),
                DropdownButtonFormField<String>(
                  initialValue: categories.any((c) => c.id == _categoryId) ? _categoryId : null,
                  decoration: _premiumDecoration(context, label: 'Category', errorText: _categoryError),
                  style: Theme.of(context).textTheme.bodyMedium,
                  items: [
                    for (final category in categories)
                      DropdownMenuItem(value: category.id, child: Text(category.name)),
                  ],
                  onChanged: (value) => setState(() {
                    _categoryId = value;
                    _categoryError = null;
                  }),
                ),
                const SizedBox(height: AppSizes.sm),
                _PremiumTapButton(onTap: _pickDate, icon: Icons.calendar_today_outlined, label: _date.fullDate),
              ],
              const SizedBox(height: AppSizes.sm),
              const SectionLabel('Due Date'),
              const SizedBox(height: AppSizes.xs),
              Builder(
                builder: (context) {
                  final scheduleId = widget.editing?.scheduleId;
                  final currentInstallments = scheduleId == null
                      ? const <Installment>[]
                      : ref.watch(installmentsStreamProvider(scheduleId)).value ?? const <Installment>[];
                  final effectiveDueDate =
                      _dueDate ?? currentInstallments.firstOrNull?.dueDate ?? _date.add(const Duration(days: 7));
                  return _PremiumTapButton(
                    onTap: () => _pickDueDate(effectiveDueDate),
                    icon: Icons.event_outlined,
                    label: effectiveDueDate.fullDate,
                  );
                },
              ),
              const SizedBox(height: AppSizes.sm),
              const SectionLabel('How to Share'),
              const SizedBox(height: AppSizes.sm),
              if (!widget.assignOnly) ...[
                SegmentedButton<SplitType>(
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  segments: const [
                    ButtonSegment(
                      value: SplitType.equal,
                      label: Text('Equal'),
                      icon: Icon(Icons.balance_rounded, size: AppSizes.iconSm),
                    ),
                    ButtonSegment(
                      value: SplitType.custom,
                      label: Text('Custom'),
                      icon: Icon(Icons.tune_rounded, size: AppSizes.iconSm),
                    ),
                    ButtonSegment(
                      value: SplitType.percentage,
                      label: Text('Percentage'),
                      icon: Icon(Icons.percent_rounded, size: AppSizes.iconSm),
                    ),
                  ],
                  selected: {_splitType},
                  onSelectionChanged: (selection) {
                    setState(() => _splitType = selection.first);
                    _revalidateSplit();
                  },
                ),
              ],
              const SizedBox(height: AppSizes.sm),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _includeMe,
                title: const Text('Include myself in this expense'),
                subtitle: const Text(
                  "Uncheck this if you paid for others only — like a gift or someone else's bill.",
                ),
                onChanged: (value) {
                  setState(() => _includeMe = value ?? true);
                  _revalidateSplit();
                },
              ),
              if (_includeMe && (_splitType == SplitType.custom || _splitType == SplitType.percentage)) ...[
                const SizedBox(height: AppSizes.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const _PersonAvatar(name: 'Me'),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: TextFormField(
                        controller: _meRow.valueController,
                        decoration: _premiumDecoration(
                          context,
                          label: 'My share (${_splitType == SplitType.percentage ? 'percent' : 'amount'})',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        onChanged: (_) {
                          if (_splitType == SplitType.custom) _meRow.locked = true;
                          _revalidateSplit();
                        },
                      ),
                    ),
                    if (_splitType == SplitType.custom)
                      _LockToggle(
                        locked: _meRow.locked,
                        onTap: () {
                          setState(() => _meRow.locked = !_meRow.locked);
                          _revalidateSplit();
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSizes.sm),
              SectionLabel(widget.assignOnly ? 'Who was this for' : 'Split Between'),
              if (widget.assignOnly && _personError != null) ...[
                const SizedBox(height: AppSizes.xs),
                Text(_personError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: AppSizes.sm),
              for (var i = 0; i < _participants.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: _ParticipantField(
                    row: _participants[i],
                    people: people,
                    showValueField: _splitType == SplitType.custom || _splitType == SplitType.percentage,
                    valueLabel: _splitType == SplitType.percentage ? 'Percent' : 'Amount',
                    mixedMode: _splitType == SplitType.custom,
                    onValueChanged: () {
                      if (_splitType == SplitType.custom) _participants[i].locked = true;
                      _revalidateSplit();
                    },
                    onToggleLock: () {
                      setState(() => _participants[i].locked = !_participants[i].locked);
                      _revalidateSplit();
                    },
                    onChanged: _revalidateSplit,
                    onRemove: widget.assignOnly || _participants.length <= 1
                        ? null
                        : () => _removeParticipant(i),
                    onCreateNewPerson: _createNewPerson,
                  ),
                ),
              if (_splitType == SplitType.custom) ...[
                Builder(
                  builder: (context) {
                    final total = double.tryParse(_amountController.text.trim());
                    final mixed = total == null ? null : _resolveMixed(total);
                    if (mixed == null) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: AppSizes.xs, bottom: AppSizes.sm),
                      child: _MixedSplitSummary(total: total!, mixed: mixed),
                    );
                  },
                ),
              ],
              if (!widget.assignOnly)
                TextButton.icon(
                  onPressed: _addParticipant,
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Add person'),
                ),
              if (_splitError != null) ...[
                const SizedBox(height: AppSizes.sm),
                Container(
                  padding: const EdgeInsets.all(AppSizes.md),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                  ),
                  child: Text(
                    _splitError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                  ),
                ),
              ],
              if (_preview != null) ...[
                const SizedBox(height: AppSizes.sm),
                _SplitPreviewCard(participants: _preview!),
              ],
              if (!_isConverting) ...[
                const SizedBox(height: AppSizes.sm),
                const SectionLabel('Notes'),
                const SizedBox(height: AppSizes.sm),
                TextFormField(
                  controller: _notesController,
                  decoration: _premiumDecoration(context, label: 'Notes (optional)'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 3,
                  textInputAction: TextInputAction.done,
                ),
              ],
              if (!_isConverting && !_isEditing) ...[
                const SizedBox(height: AppSizes.sm),
                const SectionLabel('Advanced Options'),
                const SizedBox(height: AppSizes.xs),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Don't count this in my totals"),
                  subtitle: const Text(
                    "Still shows in your history — just won't affect your balance, budgets, or reports.",
                  ),
                  value: _excludeFromCalculations,
                  onChanged: (value) => setState(() => _excludeFromCalculations = value),
                ),
                const SizedBox(height: AppSizes.sm),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Count this in a different month?'),
                  subtitle: Text(
                    _customAccountingMonth
                        ? 'Choose which month it should count toward below.'
                        : 'Right now: counted in ${_date.monthYear} (same as the date above)',
                  ),
                  value: _customAccountingMonth,
                  onChanged: (value) => setState(() {
                    _customAccountingMonth = value;
                    if (!value) _accountingMonth = DateTime(_date.year, _date.month);
                  }),
                ),
                if (_customAccountingMonth) ...[
                  const SizedBox(height: AppSizes.sm),
                  MonthYearStepper(
                    value: _accountingMonth,
                    min: DateTime(DateTime.now().year - 5, DateTime.now().month),
                    max: DateTime(DateTime.now().year + 2, DateTime.now().month),
                    onChanged: (month) => setState(() => _accountingMonth = month),
                  ),
                ],
              ],
              if (_isEditing) ...[
                const SizedBox(height: AppSizes.sm),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _deleteExpense,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(color: Theme.of(context).colorScheme.error),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Expense'),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

/// The "before you save" live preview — Total Expense, Your Spending, and
/// Money You'll Get Back, plus what each person pays. Recomputed on every
/// change from the same [ExpenseRepository.resolveShares] the save uses, so
/// the numbers shown here are exactly what gets recorded. Plain-language
/// throughout — no accounting jargon.
class _SplitPreviewCard extends StatelessWidget {
  const _SplitPreviewCard({required this.participants});

  final List<ExpenseParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final yourSpending = participants.where((p) => p.isMe).fold(0.0, (sum, p) => sum + p.share);
    final moneyBack = participants.where((p) => !p.isMe).fold(0.0, (sum, p) => sum + p.share);
    final total = yourSpending + moneyBack;

    return AppCard(
      color: context.colors.primary.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Here's how it works out", style: context.textTheme.titleSmall),
          const SizedBox(height: AppSizes.md),
          _PreviewRow(label: 'Total Expense', value: total, emphasize: true),
          _PreviewRow(label: 'Your Spending', value: yourSpending, color: AppColors.debit),
          if (moneyBack > 0) _PreviewRow(label: "Money You'll Get Back", value: moneyBack, color: AppColors.success),
          const Divider(height: AppSizes.lg),
          Text('Split Between', style: context.textTheme.labelMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: AppSizes.xs),
          for (final p in participants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.isMe ? 'You' : p.name, style: context.textTheme.bodyMedium),
                  Text(CurrencyFormatter.instance.format(p.share), style: context.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value, this.color, this.emphasize = false});

  final String label;
  final double value;
  final Color? color;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? context.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)
        : context.textTheme.bodyLarge?.copyWith(color: color, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.7))),
          Text(CurrencyFormatter.instance.format(value), style: style),
        ],
      ),
    );
  }
}

/// Read-only recap of the original expense being converted — amount,
/// category, account, date, and notes never change during a conversion
/// (only participants are added), so these are shown as plain text instead
/// of editable fields the user might mistakenly think they can change.
class _ReadOnlyExpenseSummary extends ConsumerWidget {
  const _ReadOnlyExpenseSummary({required this.prefill});

  final ConvertToSplitPrefill prefill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsStreamProvider).value ?? const [];
    final categories = ref.watch(categoriesStreamProvider).value ?? const [];
    final accountName = accounts.where((a) => a.id == prefill.accountId).firstOrNull?.name ?? 'Unknown account';
    final categoryName = categories.where((c) => c.id == prefill.categoryId).firstOrNull?.name ?? 'Uncategorized';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefill.description, style: context.textTheme.titleMedium),
          const SizedBox(height: AppSizes.xs),
          Text(
            CurrencyFormatter.instance.format(prefill.totalAmount),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSizes.sm),
          _SummaryRow(label: 'Date', value: prefill.date.fullDate),
          _SummaryRow(label: 'Account', value: accountName),
          _SummaryRow(label: 'Category', value: categoryName),
          if (prefill.notes.isNotEmpty) _SummaryRow(label: 'Notes', value: prefill.notes),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: context.textTheme.bodyMedium?.copyWith(color: context.colors.onSurface.withValues(alpha: 0.6)),
          ),
          Flexible(child: Text(value, style: context.textTheme.bodyMedium, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

/// Compact per-row indicator for [SplitType.custom]'s mixed manual/auto
/// split: an outlined "Equal" chip when auto, a filled "Manual" chip with a
/// lock glyph once the user has typed an amount for that row — tapping
/// either switches the row between the two.
class _LockToggle extends StatelessWidget {
  const _LockToggle({required this.locked, required this.onTap});

  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: AppSizes.xs),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSizes.radiusPill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.radiusPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 8),
            decoration: BoxDecoration(
              color: locked ? colors.primary.withValues(alpha: 0.12) : colors.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(AppSizes.radiusPill),
              border: Border.all(color: locked ? colors.primary.withValues(alpha: 0.3) : Colors.transparent),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: locked
                      ? Icon(Icons.lock_outline_rounded, key: const ValueKey('locked'), size: 12, color: colors.primary)
                      : Icon(
                          Icons.balance_rounded,
                          key: const ValueKey('unlocked'),
                          size: 12,
                          color: colors.onSurface.withValues(alpha: 0.5),
                        ),
                ),
                const SizedBox(width: 4),
                Text(
                  locked ? 'Manual' : 'Equal',
                  style: context.textTheme.labelSmall?.copyWith(
                    color: locked ? colors.primary : colors.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small circular initial badge giving each participant a scannable visual
/// identity in the "Custom" split rows — color chosen deterministically from
/// [AppColors.categoryPalette] by name, so the same person always gets the
/// same color without any extra state to track.
class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
    final palette = AppColors.categoryPalette;
    final color = palette[trimmed.isEmpty ? 0 : trimmed.codeUnitAt(0) % palette.length];
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Text(
        initial,
        style: context.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Live calculation banner for [SplitType.custom]'s mixed manual/auto split
/// — expense total, how much has been manually assigned, what's left, and
/// how that remainder is being shared out. Updates on every keystroke, add,
/// remove, and Manual/Equal toggle via [SplitExpenseFormSheet._resolveMixed].
class _MixedSplitSummary extends StatelessWidget {
  const _MixedSplitSummary({required this.total, required this.mixed});

  final double total;
  final MixedSplitResult mixed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final lockedFraction = total > 0 ? (mixed.lockedTotal / total).clamp(0.0, 1.0) : 0.0;
    return AppCard(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummaryRow(label: 'Expense total', value: CurrencyFormatter.instance.format(total)),
          if (mixed.lockedTotal > 0)
            _SummaryRow(label: 'Manually assigned', value: CurrencyFormatter.instance.format(mixed.lockedTotal)),
          const SizedBox(height: 2),
          Text(
            CurrencyFormatter.instance.format(mixed.remaining),
            style: context.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.primary),
          ),
          Text(
            'Remaining balance',
            style: context.textTheme.bodySmall?.copyWith(color: colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSizes.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusPill),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: lockedFraction),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: AppColors.success.withValues(alpha: 0.25),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  mixed.autoCount > 0
                      ? '${mixed.autoCount} ${mixed.autoCount == 1 ? 'person shares' : 'people share'} equally · '
                          '${CurrencyFormatter.instance.format(mixed.remaining)} ÷ ${mixed.autoCount} = '
                          '${CurrencyFormatter.instance.format(mixed.autoShare)} each'
                      : 'All participants are manually assigned',
                  style: context.textTheme.bodySmall?.copyWith(color: AppColors.success, fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.check_circle_outline_rounded, size: AppSizes.iconSm, color: AppColors.success),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sentinel dropdown value that opens [PersonFormSheet] instead of
/// selecting a person — Task 1's "create new person" one-tap ask.
const _newPersonSentinel = '__new_person__';

/// One participant row: pick an existing person from a searchable dropdown,
/// type a free-text name to add someone not tracked as a [Person], or
/// create a brand-new person without leaving this sheet. Selecting a person
/// fills the name field with their name and clears it if the dropdown
/// selection is cleared.
class _ParticipantField extends StatefulWidget {
  const _ParticipantField({
    required this.row,
    required this.people,
    required this.showValueField,
    required this.valueLabel,
    required this.onChanged,
    required this.onRemove,
    required this.onCreateNewPerson,
    this.mixedMode = false,
    this.onValueChanged,
    this.onToggleLock,
  });

  final _ParticipantRow row;
  final List<Person> people;
  final bool showValueField;
  final String valueLabel;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final VoidCallback onCreateNewPerson;

  /// [SplitType.custom]'s mixed manual/auto split — when true, [row]'s value
  /// field shows a lock toggle and displays its live auto-computed share
  /// while unlocked, instead of always being a plain manual amount field.
  final bool mixedMode;

  /// Called instead of [onChanged] when the value field itself changes in
  /// [mixedMode] — locks the row before re-solving everyone else's share.
  final VoidCallback? onValueChanged;

  /// [mixedMode] only: toggles [row.locked].
  final VoidCallback? onToggleLock;

  @override
  State<_ParticipantField> createState() => _ParticipantFieldState();
}

class _ParticipantFieldState extends State<_ParticipantField> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final validPersonId = widget.people.any((p) => p.id == row.personId) ? row.personId : null;
    final query = _searchController.text.trim().toLowerCase();
    final filteredPeople = query.isEmpty
        ? widget.people
        : widget.people.where((p) => p.name.toLowerCase().contains(query)).toList();

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.people.length > 5)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.sm),
                  child: TextField(
                    controller: _searchController,
                    decoration: _premiumDecoration(
                      context,
                      label: 'Search people',
                      prefixIcon: const Icon(Icons.search_rounded, size: AppSizes.iconSm),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              DropdownButtonFormField<String?>(
                initialValue: validPersonId,
                isExpanded: true,
                decoration: _premiumDecoration(context, label: 'Person (optional)'),
                style: Theme.of(context).textTheme.bodyMedium,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Type a name instead', overflow: TextOverflow.ellipsis),
                  ),
                  const DropdownMenuItem<String?>(
                    value: _newPersonSentinel,
                    child: Text('+ Add new person', overflow: TextOverflow.ellipsis),
                  ),
                  for (final person in filteredPeople)
                    DropdownMenuItem<String?>(
                      value: person.id,
                      child: Text(person.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value == _newPersonSentinel) {
                    widget.onCreateNewPerson();
                    return;
                  }
                  row.personId = value;
                  if (value != null) {
                    final person = widget.people.firstWhere((p) => p.id == value);
                    row.nameController.text = person.name;
                  }
                  widget.onChanged();
                },
              ),
              const SizedBox(height: AppSizes.sm),
              if (widget.mixedMode)
                Row(
                  children: [
                    _PersonAvatar(name: row.nameController.text),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: TextFormField(
                        controller: row.nameController,
                        decoration: _premiumDecoration(context, label: 'Name'),
                        style: Theme.of(context).textTheme.bodyMedium,
                        onChanged: (_) => setState(() => widget.onChanged()),
                      ),
                    ),
                  ],
                )
              else
                TextFormField(
                  controller: row.nameController,
                  decoration: _premiumDecoration(context, label: 'Name'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  onChanged: (_) => widget.onChanged(),
                ),
            ],
          ),
        ),
        if (widget.showValueField) ...[
          const SizedBox(width: AppSizes.sm),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.valueController,
              decoration: _premiumDecoration(context, label: widget.valueLabel),
              style: Theme.of(context).textTheme.bodyMedium,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => widget.mixedMode ? widget.onValueChanged?.call() : widget.onChanged(),
            ),
          ),
          if (widget.mixedMode) _LockToggle(locked: row.locked, onTap: widget.onToggleLock),
        ],
        if (widget.onRemove != null)
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'Remove person',
            onPressed: widget.onRemove,
          ),
      ],
    );

    if (!widget.mixedMode) return content;

    // "Custom" split rows get a card boundary + accent left edge that lights up once the
    // row is manually locked — a lightweight visual cue on top of the Manual/Equal chip.
    final colors = context.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(left: BorderSide(color: row.locked ? colors.primary : Colors.transparent, width: 3)),
      ),
      child: content,
    );
  }
}

/// The filled, borderless-until-focus field decoration every text/dropdown
/// field on this sheet shares — same vocabulary as `AddExpenseScreen`'s
/// `_premiumDecoration`, so switching between the plain and shared-expense
/// forms doesn't feel like two different apps. Neutral (not brand-tinted):
/// color on a form is reserved for state that means something (a selected
/// choice, a validation error), not decoration.
InputDecoration _premiumDecoration(
  BuildContext context, {
  required String label,
  String? errorText,
  Widget? prefixIcon,
}) {
  final colors = context.colors;
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    prefixIcon: prefixIcon,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
    filled: true,
    fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.5),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppSizes.radiusMd), borderSide: BorderSide.none),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.primary, width: 1.6),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: colors.error, width: 1.6),
    ),
  );
}

/// A filled icon+label tap button — the premium replacement for
/// [OutlinedButton.icon], used for the Date/Due Date pickers so they match
/// this sheet's filled-field language instead of standing out as the one
/// outlined control on the page.
class _PremiumTapButton extends StatelessWidget {
  const _PremiumTapButton({required this.onTap, required this.icon, required this.label});

  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: AppSizes.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: AppSizes.iconSm, color: colors.primary),
              const SizedBox(width: AppSizes.xs),
              Text(label, style: context.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

