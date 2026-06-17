/// Lead CSV export. The CSV generation is pure and unit-tested; the UI just
/// hands the resulting string to the clipboard.
library;

import 'package:market_coverage/main.dart';

const List<String> _leadCsvHeaders = [
  'Address',
  'Stage',
  'Score',
  'Source',
  'Condition',
  'Owner',
  'Mailing Address',
  'Out Of State',
  'Assessed Value',
  'Year Built',
  'Last Sale Date',
  'Last Sale Price',
  'ARV',
  'MAO',
  'Notes',
  'Created',
  'Latitude',
  'Longitude',
];

/// Escapes a single CSV field: wraps in quotes when it contains a comma, quote,
/// or line break, and doubles any embedded quotes (RFC 4180).
String _csvField(Object? value) {
  final text = value?.toString() ?? '';

  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r')) {
    return '"${text.replaceAll('"', '""')}"';
  }

  return text;
}

String _csvRow(Iterable<Object?> fields) => fields.map(_csvField).join(',');

/// Builds a CSV document (header + one row per lead) suitable for upload to a
/// skip-tracing service or a mail-merge. Returns just the header row when there
/// are no leads.
String leadsToCsv(List<Lead> leads) {
  final rows = <String>[_csvRow(_leadCsvHeaders)];

  for (final lead in leads) {
    rows.add(
      _csvRow([
        lead.address,
        normalizeLeadStage(lead.status),
        lead.score,
        lead.source,
        lead.condition,
        lead.parcelData.ownerName,
        lead.parcelData.mailingAddress,
        lead.parcelData.outOfStateOwner ? 'Yes' : 'No',
        lead.parcelData.assessedValue ?? '',
        lead.parcelData.yearBuilt ?? '',
        lead.saleData.lastSaleDate,
        lead.saleData.lastSalePrice ?? '',
        lead.offerData.arv ?? '',
        lead.mao ?? '',
        lead.notes,
        lead.createdAt?.toIso8601String() ?? '',
        lead.latitude ?? '',
        lead.longitude ?? '',
      ]),
    );
  }

  return rows.join('\n');
}
