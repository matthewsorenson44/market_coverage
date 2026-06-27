// Unit tests for the pure lead -> CSV export.

import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

Lead makeLead({
  String id = '1',
  String address = '123 Main St',
  String status = 'Interested',
  int score = 0,
  LeadScoreData? scoreData,
  String notes = '',
  String source = 'Driving For Dollars',
  double? assessedValue,
  DateTime? createdAt,
  double? latitude,
  double? longitude,
}) {
  return Lead(
    id: id,
    address: address,
    condition: 'Tall Grass',
    notes: notes,
    status: status,
    source: source,
    scoreData: scoreData ?? LeadScoreData.empty().copyWith(score: score),
    parcelData: LeadParcelData(
      ownerName: 'Jane Doe',
      mailingAddress: 'PO Box 1',
      outOfStateOwner: false,
      assessedValue: assessedValue,
      propertyType: '',
      lotSize: '',
      yearBuilt: null,
    ),
    reminderData: const LeadReminderData(
      lastVisitedDate: null,
      reminderDate: null,
      followUpStatus: 'None',
    ),
    offerData: const LeadOfferData(
      arv: null,
      repairCost: null,
      assignmentFee: null,
    ),
    saleData: const LeadSaleData(
      lastSaleDate: '',
      lastSalePrice: null,
      deedType: '',
      documentDate: '',
      receptionNo: '',
    ),
    createdAt: createdAt,
    latitude: latitude,
    longitude: longitude,
  );
}

void main() {
  group('leadsToCsv', () {
    test('empty list returns only the header row', () {
      final lines = leadsToCsv([]).split('\n');

      expect(lines, hasLength(1));
      expect(lines.first, startsWith('Address,Stage,Score,'));
    });

    test('one lead produces header + one data row', () {
      final lines = leadsToCsv([
        makeLead(address: '500 Oak Ave', status: 'Interested', score: 80),
      ]).split('\n');

      expect(lines, hasLength(2));
      expect(lines[1], contains('500 Oak Ave'));
      expect(lines[1], contains('Interested'));
      expect(lines[1], contains('80'));
    });

    test('normalizes legacy stage names', () {
      expect(leadsToCsv([makeLead(status: 'New')]), contains('New Lead'));
    });

    test('quotes fields that contain a comma', () {
      expect(
        leadsToCsv([makeLead(address: '123 Main St, Apt 2')]),
        contains('"123 Main St, Apt 2"'),
      );
    });

    test('doubles embedded quotes', () {
      expect(
        leadsToCsv([makeLead(notes: 'He said "sell"')]),
        contains('"He said ""sell"""'),
      );
    });

    test('null numeric fields render empty', () {
      expect(leadsToCsv([makeLead(assessedValue: null)]), contains(',,'));
    });
  });

  group('buildSkipTraceLeadsCsv', () {
    test('keeps lead_id first and honors selected columns', () {
      final csv = buildSkipTraceLeadsCsv(
        [
          makeLead(
            id: 'lead-1',
            address: '500 Oak Ave',
            score: 72,
            source: 'Referral',
            createdAt: DateTime(2026, 6, 27, 12),
          ),
        ],
        {
          SkipTraceExportColumn.leadId,
          SkipTraceExportColumn.propertyAddress,
          SkipTraceExportColumn.dateCaptured,
          SkipTraceExportColumn.leadScore,
        },
      );
      final lines = csv.split('\n');

      expect(lines.first, 'lead_id,property_address,date_captured,lead_score');
      expect(lines[1], 'lead-1,500 Oak Ave,2026-06-27,72');
      expect(csv, isNot(contains('source')));
      expect(csv, isNot(contains('Referral')));
    });

    test('condition tags are semicolon separated in one cell', () {
      final csv = buildSkipTraceLeadsCsv(
        [
          makeLead(
            scoreData: LeadScoreData.empty().copyWith(
              roofDamage: true,
              tallGrass: true,
              score: 55,
            ),
          ),
        ],
        {SkipTraceExportColumn.leadId, SkipTraceExportColumn.conditionTags},
      );

      expect(csv, contains('Roof Damage; Tall Grass'));
    });

    test('missing values export as blanks, not literal null', () {
      final csv = buildSkipTraceLeadsCsv(
        [makeLead(latitude: null, longitude: null)],
        {
          SkipTraceExportColumn.leadId,
          SkipTraceExportColumn.latitude,
          SkipTraceExportColumn.longitude,
        },
      );

      expect(csv, contains('1,,'));
      expect(csv, isNot(contains('null')));
    });
  });
}
