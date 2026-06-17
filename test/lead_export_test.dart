// Unit tests for the pure lead -> CSV export.

import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

Lead makeLead({
  String address = '123 Main St',
  String status = 'Interested',
  int score = 0,
  String notes = '',
  double? assessedValue,
}) {
  return Lead(
    id: '1',
    address: address,
    condition: 'Tall Grass',
    notes: notes,
    status: status,
    source: 'Driving For Dollars',
    scoreData: LeadScoreData.empty().copyWith(score: score),
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
    createdAt: null,
    latitude: null,
    longitude: null,
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
}
