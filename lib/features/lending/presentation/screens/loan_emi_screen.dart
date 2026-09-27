import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../emi/domain/emi_status.dart';
import '../../../emi/presentation/providers/emi_providers.dart';
import '../../../emi/presentation/screens/emis_screen.dart';
import '../../../emi/presentation/widgets/emi_form_sheet.dart';
import '../../../people/presentation/providers/people_providers.dart';
import '../../domain/loan_direction.dart';
import '../providers/loan_providers.dart';
import '../widgets/loan_card.dart';
import '../widgets/loan_emi_ui.dart';
import '../widgets/loan_form_sheet.dart';
import 'loans_screen.dart';

enum LoanEmiTab { loans, emis }

/// The single Loan & EMI section: what you owe and what's due next at the
/// top, a Loans | EMIs switch, and one Add that asks "Loan or EMI?" before
/// opening that existing form. Mirrors the web app's `LoanEmiWorkspace`.
/// Both lists stay mounted so each keeps its own search/filter state.
class LoanEmiScreen extends ConsumerStatefulWidget {
  const LoanEmiScreen({super.key, this.initialTab = LoanEmiTab.loans});

  final LoanEmiTab initialTab;

  @override
  ConsumerState<LoanEmiScreen> createState() => _LoanEmiScreenState();
}

class _LoanEmiScreenState extends ConsumerState<LoanEmiScreen> {
  late LoanEmiTab _tab = widget.initialTab;

  Future<void> _add() async {
    final kind = await LoanEmiAddChooser.show(context);
    if (kind == null || !mounted) return;
    await _open(kind);
  }

  Future<void> _open(LoanEmiTab kind) async {
    setState(() => _tab = kind);
    switch (kind) {
      case LoanEmiTab.loans:
        await LoanFormSheet.show(context);
      case LoanEmiTab.emis:
        await EmiFormSheet.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loansAsync = ref.watch(loansStreamProvider);
    final emisAsync = ref.watch(emisStreamProvider);
    final loans = loansAsync.value ?? const [];
    final emis = emisAsync.value ?? const [];

    // First run: nothing to summarize yet — explain Loan vs EMI instead.
    if (loansAsync.hasValue &&
        emisAsync.hasValue &&
        loans.isEmpty &&
        emis.isEmpty) {
      return _FirstRunScreen(onPick: _open);
    }

    final header = _LoanEmiHeader(
      tab: _tab,
      loanCount: loans.length,
      emiCount: emis.length,
      onTabChanged: (tab) => setState(() => _tab = tab),
    );
    return IndexedStack(
      index: _tab.index,
      children: [
        LoansScreen(title: 'Loan & EMI', header: header, onAddRequest: _add),
        EmisScreen(title: 'Loan & EMI', header: header, onAddRequest: _add),
      ],
    );
  }
}

/// Summary + switch, scrolling with the list so the screen stays compact.
class _LoanEmiHeader extends ConsumerWidget {
  const _LoanEmiHeader({
    required this.tab,
    required this.loanCount,
    required this.emiCount,
    required this.onTabChanged,
  });

  final LoanEmiTab tab;
  final int loanCount;
  final int emiCount;
  final ValueChanged<LoanEmiTab> onTabChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        AppSizes.xs,
        AppSizes.lg,
        AppSizes.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SummaryCard(),
          const SizedBox(height: AppSizes.md),
          SegmentedButton<LoanEmiTab>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.standard,
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(44)),
            ),
            segments: [
              ButtonSegment(
                value: LoanEmiTab.loans,
                icon: const Icon(LoanEmiCopy.loanIcon, size: 18),
                label: Text('${LoanEmiCopy.loans} · $loanCount'),
              ),
              ButtonSegment(
                value: LoanEmiTab.emis,
                icon: const Icon(LoanEmiCopy.emiIcon, size: 18),
                label: Text('${LoanEmiCopy.emis} · $emiCount'),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (selection) => onTabChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

/// Total outstanding, active counts, and the single next installment across
/// both Loans and EMIs. Sums only the existing per-record provider figures —
/// the same ones the dashboard's "To Pay" and "Remaining loan balance" use.
class _SummaryCard extends ConsumerWidget {
  const _SummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = loanEmiSecondaryText(context);
    final owed =
        ref.watch(totalAmountToPayProvider) +
        ref.watch(totalRemainingEmiBalanceProvider);
    final toReceive = ref.watch(totalAmountToReceiveProvider);
    final activeLoans = ref.watch(activeLoansProvider);
    final activeEmiCount = ref
        .watch(activeEmisProvider)
        .where((e) => ref.watch(emiStatusProvider(e)) != EmiStatus.completed)
        .length;
    final people = ref.watch(peopleStreamProvider).value ?? const [];

    // Earliest upcoming installment across borrowed loans and EMIs.
    ({String name, DateTime date, double amount})? next;
    for (final loan in activeLoans) {
      if (loan.direction != LoanDirection.taken) continue;
      final installment = ref.watch(loanNextUpcomingInstallmentProvider(loan));
      if (installment == null) continue;
      if (next == null || installment.dueDate.isBefore(next.date)) {
        final person = people.where((p) => p.id == loan.personId).firstOrNull;
        next = (
          name: loanCardTitle(loan, person),
          date: installment.dueDate,
          amount: installment.remainingAmount,
        );
      }
    }
    final nextEmi = ref.watch(nextEmiDueProvider);
    if (nextEmi != null &&
        (next == null || nextEmi.installment.dueDate.isBefore(next.date))) {
      next = (
        name: nextEmi.emi.name,
        date: nextEmi.installment.dueDate,
        amount: nextEmi.installment.remainingAmount,
      );
    }
    final nextDays = next == null ? null : loanEmiDaysUntil(next.date);

    TextStyle? label() => context.textTheme.labelSmall?.copyWith(
      color: secondary,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    );

    return Container(
      padding: const EdgeInsets.all(AppSizes.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusCard),
        border: Border.all(color: context.colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('TOTAL OUTSTANDING', style: label()),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormatter.instance.format(owed),
              style: context.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (toReceive > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '+ ${CurrencyFormatter.instance.format(toReceive)}',
                      style: const TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const TextSpan(text: ' lent, still to receive'),
                  ],
                ),
                style: context.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
            child: Divider(height: 1, color: context.colors.outline),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE', style: label()),
                      const SizedBox(height: 4),
                      _count(context, activeLoans.length, 'Loan', 'Loans'),
                      _count(context, activeEmiCount, 'EMI', 'EMIs'),
                    ],
                  ),
                ),
                VerticalDivider(width: AppSizes.xl, color: context.colors.outline),
                Expanded(
                  flex: 6,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('NEXT INSTALLMENT', style: label()),
                      const SizedBox(height: 4),
                      if (next == null)
                        Text(
                          'Nothing due',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        )
                      else ...[
                        Text(
                          CurrencyFormatter.instance.format(next.amount),
                          style: context.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          next.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTheme.bodySmall,
                        ),
                        Text(
                          loanEmiDueLabel(next.date),
                          style: context.textTheme.labelMedium?.copyWith(
                            color: nextDays! < 0
                                ? AppColors.error
                                : nextDays <= 3
                                ? AppColors.warning
                                : secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _count(BuildContext context, int count, String one, String many) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$count ',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          TextSpan(text: count == 1 ? one : many),
        ],
      ),
      style: context.textTheme.bodyMedium,
    );
  }
}

/// Shown when the user has no Loans or EMIs yet: what each one means, and a
/// big, thumb-friendly way to add the first.
class _FirstRunScreen extends StatelessWidget {
  const _FirstRunScreen({required this.onPick});

  final ValueChanged<LoanEmiTab> onPick;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loan & EMI')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.lg,
          AppSizes.sm,
          AppSizes.lg,
          AppSizes.xl,
        ),
        children: [
          Text(
            'Track what you owe in one place',
            style: context.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            "Add a Loan or an EMI and FlowFi builds its installment schedule, "
            "shows what's due next, and keeps the outstanding balance up to "
            'date as you pay.',
            style: context.textTheme.bodyMedium?.copyWith(
              color: loanEmiSecondaryText(context),
            ),
          ),
          const SizedBox(height: AppSizes.xl),
          LoanEmiChoiceTile(
            kind: LoanEmiTab.loans,
            large: true,
            onTap: () => onPick(LoanEmiTab.loans),
          ),
          const SizedBox(height: AppSizes.md),
          LoanEmiChoiceTile(
            kind: LoanEmiTab.emis,
            large: true,
            onTap: () => onPick(LoanEmiTab.emis),
          ),
        ],
      ),
    );
  }
}

/// One "Loan" / "EMI" choice — shared by the Add chooser and first run.
class LoanEmiChoiceTile extends StatelessWidget {
  const LoanEmiChoiceTile({
    super.key,
    required this.kind,
    required this.onTap,
    this.large = false,
  });

  final LoanEmiTab kind;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final isLoan = kind == LoanEmiTab.loans;
    final radius = BorderRadius.circular(AppSizes.radiusMd);
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: context.colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(large ? AppSizes.lg : AppSizes.md),
          child: Row(
            children: [
              LoanEmiIconBox(
                icon: isLoan ? LoanEmiCopy.loanIcon : LoanEmiCopy.emiIcon,
                size: large ? 48 : 44,
              ),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLoan ? LoanEmiCopy.loan : LoanEmiCopy.emi,
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoan
                          ? LoanEmiCopy.loanDescription
                          : LoanEmiCopy.emiDescription,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: loanEmiSecondaryText(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Icon(
                Icons.chevron_right_rounded,
                color: loanEmiSecondaryText(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "What are you adding?" — a short bottom sheet with two rows. Resolves to
/// the picked kind, or null when dismissed.
class LoanEmiAddChooser extends StatelessWidget {
  const LoanEmiAddChooser({super.key});

  static Future<LoanEmiTab?> show(BuildContext context) {
    return showModalBottomSheet<LoanEmiTab>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const LoanEmiAddChooser(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.lg,
        0,
        AppSizes.lg,
        AppSizes.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What are you adding?',
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSizes.md),
          for (final kind in LoanEmiTab.values) ...[
            LoanEmiChoiceTile(
              kind: kind,
              onTap: () => Navigator.of(context).pop(kind),
            ),
            if (kind != LoanEmiTab.values.last)
              const SizedBox(height: AppSizes.sm),
          ],
        ],
      ),
    );
  }
}
