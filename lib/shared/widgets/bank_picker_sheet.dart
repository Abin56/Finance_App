import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/data/bank_registry.dart';
import '../../core/models/bank_info.dart';
import 'bank_avatar.dart';

/// Searchable Indian bank picker. Returns the chosen [BankInfo.id]; `null`
/// means the sheet was dismissed with no change. Picking "Other / Generic
/// Bank" explicitly returns [BankRegistry.generic.id] so callers can tell
/// an intentional clear apart from a dismiss.
class BankPickerSheet extends StatefulWidget {
  const BankPickerSheet({super.key, this.currentBankId});

  final String? currentBankId;

  static Future<String?> show(BuildContext context, {String? currentBankId}) {
    return showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BankPickerSheet(currentBankId: currentBankId),
    );
  }

  @override
  State<BankPickerSheet> createState() => _BankPickerSheetState();
}

class _BankPickerSheetState extends State<BankPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BankInfo> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return BankRegistry.all
        .where((b) => b.name.toLowerCase().contains(query) || b.shortCode.toLowerCase().contains(query))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _select(String? bankId) => Navigator.of(context).pop(bankId);

  @override
  Widget build(BuildContext context) {
    final showingSearch = _query.trim().isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSizes.lg),
              Text('Select bank', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSizes.md),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search by bank name or short name',
                  isDense: true,
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: AppSizes.sm),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const BankAvatar(),
                      title: const Text('Other / Generic Bank'),
                      subtitle: const Text('Clear bank selection'),
                      onTap: () => _select(BankRegistry.generic.id),
                    ),
                    const Divider(),
                    if (showingSearch) ..._buildSearchResults() else ..._buildBrowseList(),
                  ],
                ),
              ),
              const SizedBox(height: AppSizes.lg),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildSearchResults() {
    final results = _filtered;
    if (results.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSizes.xl),
          child: Center(child: Text('No banks match your search')),
        ),
      ];
    }
    return [for (final bank in results) _BankRow(bank: bank, onTap: () => _select(bank.id))];
  }

  List<Widget> _buildBrowseList() {
    final widgets = <Widget>[];
    final frequent = BankRegistry.frequent;
    if (frequent.isNotEmpty) {
      widgets.add(const _SectionHeader('Frequently used'));
      widgets.addAll([for (final bank in frequent) _BankRow(bank: bank, onTap: () => _select(bank.id))]);
    }
    final grouped = BankRegistry.groupedByLetter;
    for (final letter in grouped.keys.toList()..sort()) {
      widgets.add(_SectionHeader(letter));
      widgets.addAll([for (final bank in grouped[letter]!) _BankRow(bank: bank, onTap: () => _select(bank.id))]);
    }
    return widgets;
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({required this.bank, required this.onTap});

  final BankInfo bank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: BankAvatar(bankId: bank.id, size: 36),
      title: Text(bank.name),
      subtitle: Text(bank.shortCode),
      onTap: onTap,
    );
  }
}
