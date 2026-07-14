import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/extensions/date_extensions.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/person.dart';
import '../../domain/person_timeline_builder.dart';
import '../../domain/person_timeline_entry.dart';
import 'share_format.dart';

/// Builds a plain-text formatted statement and hands it to the platform's
/// native share sheet (WhatsApp/SMS/Email all accept shared text). PDF
/// export is explicitly deferred to a later milestone — this is a
/// well-structured text layout, not a document.
abstract class ShareStatement {
  ShareStatement._();

  static String buildText(Person person, List<PersonTimelineEntry> entriesOldestFirst) {
    final buffer = StringBuffer()
      ..writeln(ShareFormat.header('Statement for ${person.name}'))
      ..writeln('Generated ${DateTime.now().fullDate}')
      ..writeln()
      ..writeln('Starting Amount Left: ${CurrencyFormatter.instance.format(person.openingBalance)}')
      ..writeln(ShareFormat.divider);

    final balanceAfterById = PersonTimelineBuilder.runningBalances(
      openingBalance: person.openingBalance,
      entriesOldestFirst: entriesOldestFirst,
    );

    for (final entry in entriesOldestFirst) {
      final sign = entry.signedAmount >= 0 ? '+' : '-';
      final runningBalance = balanceAfterById[entry.id]!;
      final dot = entry.status == null ? '' : '${ShareFormat.statusDot(entry.status)} ';
      buffer.writeln('$dot${entry.date.shortDate}  ${entry.title}');
      buffer.writeln('  $sign${CurrencyFormatter.instance.format(entry.signedAmount.abs())}'
          '  →  Amount Left: ${CurrencyFormatter.instance.format(runningBalance)}');
      if (entry.note.isNotEmpty) buffer.writeln('  Note: ${entry.note}');
      buffer.writeln();
    }

    buffer
      ..writeln(ShareFormat.divider)
      ..writeln('Amount Left: ${CurrencyFormatter.instance.format(person.currentBalance.abs())}'
          ' (${person.isCreditor ? 'owes you' : person.isDebtor ? 'you owe' : 'all paid up'})')
      ..writeln()
      ..writeln(ShareFormat.footer);

    return buffer.toString();
  }

  static Future<void> share(BuildContext context, Person person, List<PersonTimelineEntry> entriesOldestFirst) {
    final text = buildText(person, entriesOldestFirst);
    return SharePlus.instance.share(ShareParams(text: text, subject: 'Statement for ${person.name}'));
  }
}
