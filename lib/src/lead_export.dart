/// Lead CSV export. The CSV generation is pure and unit-tested.
library;

import 'package:csv/csv.dart';
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

/// Builds a CSV document (header + one row per lead) suitable for upload to a
/// skip-tracing service or a mail-merge. Returns just the header row when there
/// are no leads.
String leadsToCsv(List<Lead> leads) {
  final rows = <List<Object?>>[
    _leadCsvHeaders,
    for (final lead in leads)
      [
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
      ],
  ];

  return const ListToCsvConverter(eol: '\n').convert(rows);
}
