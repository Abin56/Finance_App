import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/payment_schedule/domain/installment.dart';
import '../../../../core/payment_schedule/domain/installment_status.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/expense.dart';
import '../../domain/expense_participant.dart';
import '../widgets/share_expense.dart';

/// Full-screen preview of the shareable expense receipt, opened by
/// [ShareExpense.share] before anything leaves the app. Renders the split
/// as a banking-app-style receipt card (always light, so the shared file
/// looks identical regardless of the sender's theme) and offers three
/// export formats: the receipt as an image, the same capture wrapped in a
/// PDF, or the original [ShareExpense.buildText] plain text. All amounts
/// come from the exact same expense/installment fields the old text share
/// used — this screen only changes presentation, never the numbers.
class ShareExpensePreviewScreen extends StatefulWidget {
  const ShareExpensePreviewScreen({super.key, required this.expense, required this.installments});

  final Expense expense;
  final List<Installment> installments;

  static Future<void> open(BuildContext context, Expense expense, List<Installment> installments) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShareExpensePreviewScreen(expense: expense, installments: installments),
      ),
    );
  }

  @override
  State<ShareExpensePreviewScreen> createState() => _ShareExpensePreviewScreenState();
}

class _ShareExpensePreviewScreenState extends State<ShareExpensePreviewScreen> {
  final _receiptKey = GlobalKey();
  bool _busy = false;

  Future<Uint8List> _captureReceiptPng() async {
    final boundary = _receiptKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }

  Future<XFile> _writeTempFile(String name, Uint8List bytes, String mimeType) async {
    final dir = await getTemporaryDirectory();
    final file = XFile.fromData(bytes, mimeType: mimeType);
    final path = '${dir.path}/$name';
    await file.saveTo(path);
    return XFile(path, mimeType: mimeType);
  }

  String get _fileStem {
    final slug = widget.expense.description
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'flowfi_${slug.isEmpty ? 'expense' : slug.toLowerCase()}';
  }

  Future<void> _runShare(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareImage() => _runShare(() async {
        final png = await _captureReceiptPng();
        final file = await _writeTempFile('$_fileStem.png', png, 'image/png');
        await SharePlus.instance.share(
          ShareParams(files: [file], subject: 'Expense: ${widget.expense.description}'),
        );
      });

  Future<void> _sharePdf() => _runShare(() async {
        final png = await _captureReceiptPng();
        final receipt = pw.MemoryImage(png);
        final doc = pw.Document(title: 'Expense: ${widget.expense.description}', producer: 'FlowFi');
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(36),
            build: (_) => pw.Center(
              child: pw.Image(receipt, fit: pw.BoxFit.contain),
            ),
          ),
        );
        final file = await _writeTempFile('$_fileStem.pdf', await doc.save(), 'application/pdf');
        await SharePlus.instance.share(
          ShareParams(files: [file], subject: 'Expense: ${widget.expense.description}'),
        );
      });

  Future<void> _shareText() => _runShare(() async {
        await SharePlus.instance.share(
          ShareParams(
            text: ShareExpense.buildText(widget.expense, widget.installments),
            subject: 'Expense: ${widget.expense.description}',
          ),
        );
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Expense')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: RepaintBoundary(
                    key: _receiptKey,
                    child: _ExpenseReceipt(expense: widget.expense, installments: widget.installments),
                  ),
                ),
              ),
            ),
          ),
          _ShareActionsBar(
            busy: _busy,
            onShareImage: _shareImage,
            onSharePdf: _sharePdf,
            onShareText: _shareText,
          ),
        ],
      ),
    );
  }
}

/// The sticky bottom bar with the three export actions. Image is the
/// primary (filled) action since it matches the preview exactly.
class _ShareActionsBar extends StatelessWidget {
  const _ShareActionsBar({
    required this.busy,
    required this.onShareImage,
    required this.onSharePdf,
    required this.onShareText,
  });

  final bool busy;
  final VoidCallback onShareImage;
  final VoidCallback onSharePdf;
  final VoidCallback onShareText;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSizes.lg, AppSizes.md, AppSizes.lg, AppSizes.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                height: AppSizes.buttonHeight,
                child: FilledButton.icon(
                  onPressed: busy ? null : onShareImage,
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.ios_share_rounded),
                  label: const Text('Share Receipt'),
                ),
              ),
              const SizedBox(height: AppSizes.sm),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onSharePdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: AppSizes.iconSm),
                      label: const Text('PDF'),
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: busy ? null : onShareText,
                      icon: const Icon(Icons.notes_rounded, size: AppSizes.iconSm),
                      label: const Text('Text'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The receipt card itself — deliberately styled with fixed light colors
/// (not the app theme) so the captured image/PDF looks the same for every
/// sender. Numbers mirror `ShareExpense.buildText` exactly: collected and
/// remaining sum the schedule's installments, and each participant row
/// falls back to `share`/0 when untracked, same as the text share.
class _ExpenseReceipt extends StatelessWidget {
  const _ExpenseReceipt({required this.expense, required this.installments});

  final Expense expense;
  final List<Installment> installments;

  static const _ink = AppColors.lightTextPrimary;
  static const _muted = AppColors.lightTextSecondary;

  @override
  Widget build(BuildContext context) {
    final fmt = CurrencyFormatter.instance;
    final installmentById = {for (final i in installments) i.id: i};
    final collected = installments.fold(0.0, (sum, i) => sum + i.amountPaid);
    final remaining = installments.fold(0.0, (sum, i) => sum + i.remainingAmount);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightSurface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.lightOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          Padding(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  expense.description,
                  style: context.textTheme.titleLarge?.copyWith(color: _ink, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(expense.date.fullDate, style: context.textTheme.bodySmall?.copyWith(color: _muted)),
                const SizedBox(height: AppSizes.lg),
                Center(
                  child: Column(
                    children: [
                      Text('TOTAL BILL',
                          style: context.textTheme.labelSmall?.copyWith(color: _muted, letterSpacing: 1.4)),
                      const SizedBox(height: AppSizes.xs),
                      Text(
                        fmt.format(expense.totalAmount),
                        style: context.textTheme.headlineMedium?.copyWith(color: _ink, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSizes.lg),
                Row(
                  children: [
                    Expanded(
                      child: _summaryTile(context, label: 'Collected', amount: fmt.format(collected), color: AppColors.success),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: _summaryTile(context, label: 'To Settle', amount: fmt.format(remaining), color: AppColors.pending),
                    ),
                  ],
                ),
                const SizedBox(height: AppSizes.lg),
                _sectionLabel(context, 'SPLIT DETAILS'),
                const SizedBox(height: AppSizes.sm),
                for (final participant in expense.participants) ...[
                  _ParticipantRow(
                    participant: participant,
                    installment: installmentById[participant.installmentId],
                  ),
                  if (participant != expense.participants.last)
                    const Divider(height: AppSizes.lg, color: AppColors.lightOutline),
                ],
                const SizedBox(height: AppSizes.lg),
                _dashedDivider(),
                const SizedBox(height: AppSizes.md),
                _totalRow(context, 'Total Bill', fmt.format(expense.totalAmount)),
                _totalRow(context, 'Collected', fmt.format(collected)),
                _totalRow(context, 'To Settle', fmt.format(remaining), emphasized: true),
              ],
            ),
          ),
          _footer(context),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: AppColors.primaryGradient),
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg - 1)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: AppSizes.iconMd),
          const SizedBox(width: AppSizes.sm),
          Text(
            'FlowFi',
            style: context.textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            'EXPENSE RECEIPT',
            style: context.textTheme.labelSmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg, vertical: AppSizes.md),
      decoration: const BoxDecoration(
        color: AppColors.lightBackground,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSizes.radiusLg - 1)),
      ),
      child: Column(
        children: [
          Text(
            'Please pay your share to settle this expense.',
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(color: _ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            'Generated by FlowFi • Your Money. Clearly Managed.',
            textAlign: TextAlign.center,
            style: context.textTheme.labelSmall?.copyWith(color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: context.textTheme.labelSmall?.copyWith(color: _muted, letterSpacing: 1.4, fontWeight: FontWeight.w600),
    );
  }

  Widget _summaryTile(BuildContext context, {required String label, required String amount, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md, horizontal: AppSizes.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Column(
        children: [
          Text(label, style: context.textTheme.labelSmall?.copyWith(color: _muted)),
          const SizedBox(height: AppSizes.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount,
              style: context.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String amount, {bool emphasized = false}) {
    final style = emphasized
        ? context.textTheme.titleMedium?.copyWith(color: _ink, fontWeight: FontWeight.w700)
        : context.textTheme.bodyMedium?.copyWith(color: _muted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(amount, style: style?.copyWith(color: emphasized ? _ink : _ink))],
      ),
    );
  }

  Widget _dashedDivider() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 5.0;
        final count = (constraints.maxWidth / (dashWidth * 2)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => const SizedBox(width: dashWidth, height: 1, child: ColoredBox(color: AppColors.lightOutline)),
          ),
        );
      },
    );
  }
}

/// One participant line: name + settlement status pill on the left,
/// share / paid / remaining amounts on the right. Fallbacks for untracked
/// participants match `ShareExpense.buildText` (paid = share, remaining = 0).
class _ParticipantRow extends StatelessWidget {
  const _ParticipantRow({required this.participant, required this.installment});

  final ExpenseParticipant participant;
  final Installment? installment;

  ({String label, Color color}) get _status {
    if (participant.isMe) return (label: 'Payer', color: AppColors.info);
    switch (installment?.status) {
      case InstallmentStatus.paid:
        return (label: 'Paid', color: AppColors.success);
      case InstallmentStatus.partiallyPaid:
        return (label: 'Partial', color: AppColors.warning);
      case InstallmentStatus.overdue:
        return (label: 'Overdue', color: AppColors.error);
      case InstallmentStatus.upcoming:
      case InstallmentStatus.skipped:
        return (label: 'Pending', color: AppColors.pending);
      // Same "no status" bucket as the text share's ⚪ — a participant with
      // no tracking installment, so we don't claim paid or pending.
      case null:
        return (label: 'Untracked', color: AppColors.lightTextSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = CurrencyFormatter.instance;
    final paid = installment?.amountPaid ?? participant.share;
    final remaining = installment?.remainingAmount ?? 0;
    final status = _status;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                participant.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: _ExpenseReceipt._ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSizes.radiusPill),
                ),
                child: Text(
                  status.label,
                  style: context.textTheme.labelSmall?.copyWith(color: status.color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              fmt.format(participant.share),
              style: context.textTheme.bodyMedium?.copyWith(color: _ExpenseReceipt._ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Paid ${fmt.format(paid)}${remaining > 0 ? ' • Due ${fmt.format(remaining)}' : ''}',
              style: context.textTheme.labelSmall?.copyWith(
                color: remaining > 0 ? AppColors.pending : _ExpenseReceipt._muted,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
