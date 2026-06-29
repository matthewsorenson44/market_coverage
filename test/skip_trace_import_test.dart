import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

Lead makeImportLead({
  String id = 'lead-1',
  String address = '123 Main St',
  String ownerName = '',
  String ownerPhone = '',
  String ownerPhone2 = '',
  String ownerEmail = '',
  bool skipTraced = false,
}) {
  return Lead(
    id: id,
    address: address,
    condition: 'Tall Grass',
    notes: 'Do not overwrite',
    scoreData: LeadScoreData.empty().copyWith(score: 42),
    parcelData: LeadParcelData(
      ownerName: ownerName,
      mailingAddress: '',
      outOfStateOwner: false,
      assessedValue: null,
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
    ownerPhone: ownerPhone,
    ownerPhone2: ownerPhone2,
    ownerEmail: ownerEmail,
    skipTraced: skipTraced,
    createdAt: DateTime(2026, 6, 28),
  );
}

void main() {
  group('buildSkipTraceImportPreview', () {
    test(
      'matches by lead id, fills blanks only, and reports unmatched rows',
      () {
        final now = DateTime(2026, 6, 28, 12);
        final leads = [
          makeImportLead(
            id: 'lead-1',
            address: '123 Main St',
            ownerName: 'Existing Owner',
            ownerPhone: '555-0000',
          ),
          makeImportLead(id: 'lead-2', address: '456 Oak Ave'),
        ];
        final rows = [
          [
            'lead_id',
            'property_address',
            'owner_name',
            'owner_phone',
            'owner_phone_2',
            'owner_email',
          ],
          [
            'lead-1',
            '123 Main St',
            'New Owner',
            '555-1111',
            '555-2222',
            'owner@example.com',
          ],
          ['missing', '999 Missing St', 'No Match', '555-9999', '', ''],
        ];

        final preview = buildSkipTraceImportPreview(leads, rows, now);

        expect(preview.enrichments, hasLength(1));
        expect(preview.unmatchedRows, ['missing']);
        expect(preview.phoneFirstTimeCount, 0);

        final enrichment = preview.enrichments.single;
        expect(enrichment.leadId, 'lead-1');
        expect(enrichment.ownerName, isNull);
        expect(enrichment.ownerPhone, isNull);
        expect(enrichment.ownerPhone2, '555-2222');
        expect(enrichment.ownerEmail, 'owner@example.com');
        expect(enrichment.toUpdateMap(), isNot(contains('notes')));
        expect(enrichment.toUpdateMap(), isNot(contains('lead_score')));
      },
    );

    test('falls back to normalized property address when lead_id is blank', () {
      final now = DateTime(2026, 6, 28, 12);
      final lead = makeImportLead(id: 'lead-2', address: '456 Oak Ave');
      final rows = [
        ['address', 'owner', 'phone', 'email'],
        [' 456 oak ave ', 'Address Owner', '555-0101', 'test@example.com'],
      ];

      final preview = buildSkipTraceImportPreview([lead], rows, now);

      expect(preview.enrichments, hasLength(1));
      expect(preview.unmatchedRows, isEmpty);
      expect(preview.phoneFirstTimeCount, 1);
      expect(preview.enrichments.single.leadId, 'lead-2');
      expect(preview.enrichments.single.ownerName, 'Address Owner');
      expect(preview.enrichments.single.ownerPhone, '555-0101');
      expect(preview.enrichments.single.ownerEmail, 'test@example.com');
    });

    test(
      'throws the exact message when no lead_id or address column exists',
      () {
        final rows = [
          ['owner_phone', 'owner_email'],
          ['555-0101', 'test@example.com'],
        ];

        expect(
          () => buildSkipTraceImportPreview([], rows, DateTime(2026, 6, 28)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              skipTraceImportMissingMatcherMessage,
            ),
          ),
        );
      },
    );

    test('blank returned cells do not create enrichment updates', () {
      final lead = makeImportLead(id: 'lead-1', address: '123 Main St');
      final rows = [
        ['lead_id', 'owner_phone', 'owner_email'],
        ['lead-1', '', ''],
      ];

      final preview = buildSkipTraceImportPreview(
        [lead],
        rows,
        DateTime(2026, 6, 28),
      );

      expect(preview.enrichments, isEmpty);
      expect(preview.phoneFirstTimeCount, 0);
    });
  });
}
