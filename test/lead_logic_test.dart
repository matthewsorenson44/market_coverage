// Unit tests for the pure business logic in main.dart: offer math, parsing,
// address handling, stage normalization, geo/mileage, and formatting.
//
// These cover the money-critical and data-parsing paths without touching
// Supabase or the UI.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:market_coverage/main.dart';

void main() {
  group('LeadOfferData.mao (70% rule)', () {
    test('null ARV yields null MAO', () {
      const offer = LeadOfferData(
        arv: null,
        repairCost: 30000,
        assignmentFee: 10000,
      );
      expect(offer.mao, isNull);
    });

    test('full formula: 70% ARV minus repairs and fee', () {
      const offer = LeadOfferData(
        arv: 200000,
        repairCost: 30000,
        assignmentFee: 10000,
      );
      // 0.70 * 200000 - 30000 - 10000 = 100000
      expect(offer.mao, 100000);
    });

    test('missing repair/fee treated as zero', () {
      const offer = LeadOfferData(
        arv: 100000,
        repairCost: null,
        assignmentFee: null,
      );
      expect(offer.mao, 70000);
    });
  });

  group('normalizeLeadStage', () {
    test('maps legacy stage names to current ones', () {
      expect(normalizeLeadStage('New'), 'New Lead');
      expect(normalizeLeadStage('Follow Up'), 'Contact Needed');
      expect(normalizeLeadStage('Offer Made'), 'Offer Sent');
      expect(normalizeLeadStage('Dead'), 'Dead Lead');
    });

    test('passes through valid current stages', () {
      expect(normalizeLeadStage('Interested'), 'Interested');
      expect(normalizeLeadStage('Under Contract'), 'Under Contract');
    });

    test('unknown stage falls back to New Lead', () {
      expect(normalizeLeadStage('Banana'), 'New Lead');
    });
  });

  group('normalizedAddressKey', () {
    test('null returns empty string', () {
      expect(normalizedAddressKey(null), '');
    });

    test('strips punctuation/case and normalizes common tokens', () {
      expect(
        normalizedAddressKey('123 North Main Street'),
        normalizedAddressKey('123 n main st'),
      );
    });

    test('different addresses produce different keys', () {
      expect(
        normalizedAddressKey('123 Main St, Tulsa OK') ==
            normalizedAddressKey('PO Box 5, Dallas TX'),
        isFalse,
      );
    });
  });

  group('houseNumberFromAddress', () {
    test('extracts leading number', () {
      expect(houseNumberFromAddress('123 Main St'), '123');
    });

    test('handles alphanumeric house numbers', () {
      expect(houseNumberFromAddress('12A Oak Ave'), '12A');
    });

    test('null or no leading number returns null', () {
      expect(houseNumberFromAddress(null), isNull);
      expect(houseNumberFromAddress('Main Street'), isNull);
    });
  });

  group('parcel value parsers', () {
    test('cleanParcelText trims and nullifies empties', () {
      expect(cleanParcelText('  hi  '), 'hi');
      expect(cleanParcelText('   '), isNull);
      expect(cleanParcelText(null), isNull);
    });

    test('parseParcelDouble handles num, string, garbage', () {
      expect(parseParcelDouble(5), 5.0);
      expect(parseParcelDouble('42.5'), 42.5);
      expect(parseParcelDouble('nope'), isNull);
      expect(parseParcelDouble(null), isNull);
    });

    test('parseParcelInt handles num, string, garbage', () {
      expect(parseParcelInt(5.9), 5);
      expect(parseParcelInt('7'), 7);
      expect(parseParcelInt('nope'), isNull);
    });

    test('parseCoordinate handles num and string', () {
      expect(parseCoordinate(-95.8), -95.8);
      expect(parseCoordinate('36.27'), 36.27);
      expect(parseCoordinate('bad'), isNull);
    });

    test('firstParcelDouble returns first positive parseable value', () {
      expect(firstParcelDouble([null, 0, '42']), 42.0);
      expect(firstParcelDouble([0, -5]), isNull);
      expect(firstParcelDouble([]), isNull);
    });
  });

  group('combineMailingAddress', () {
    test('empty attributes returns null', () {
      expect(combineMailingAddress(<String, dynamic>{}), isNull);
    });

    test('combines line, city, state, zip', () {
      final result = combineMailingAddress(<String, dynamic>{
        'Address1': '100 Elm St',
        'City': 'Tulsa',
        'State': 'OK',
        'ZIPCode': '74101',
      });
      expect(result, contains('100 Elm St'));
      expect(result, contains('Tulsa, OK, 74101'));
    });
  });

  group('formatMoney', () {
    test('null is "Not set"', () => expect(formatMoney(null), 'Not set'));
    test('zero', () => expect(formatMoney(0), r'$0'));
    test('thousands separator', () {
      expect(formatMoney(1234567), r'$1,234,567');
      expect(formatMoney(1000), r'$1,000');
    });
    test('rounds to whole dollars', () => expect(formatMoney(999.4), r'$999'));
    test('negative', () => expect(formatMoney(-2500), r'-$2,500'));
  });

  group('date helpers', () {
    test('formatDateOnly', () {
      expect(formatDateOnly(DateTime(2024, 3, 5)), '2024-03-05');
      expect(formatDateOnly(null), isNull);
    });

    test('isSameDate ignores time component', () {
      expect(
        isSameDate(DateTime(2024, 1, 1, 15, 30), DateTime(2024, 1, 1)),
        isTrue,
      );
      expect(isSameDate(DateTime(2024, 1, 2), DateTime(2024, 1, 1)), isFalse);
      expect(isSameDate(null, DateTime(2024, 1, 1)), isFalse);
    });

    test('isBeforeDate', () {
      expect(isBeforeDate(DateTime(2024, 1, 1), DateTime(2024, 1, 2)), isTrue);
      expect(isBeforeDate(DateTime(2024, 1, 2), DateTime(2024, 1, 1)), isFalse);
      expect(isBeforeDate(null, DateTime(2024, 1, 1)), isFalse);
    });
  });

  group('leadScoreColor thresholds', () {
    test('cold (<40) is green', () {
      expect(leadScoreColor(0), Colors.green);
      expect(leadScoreColor(39), Colors.green);
    });
    test('warm (40-69) is amber', () {
      expect(leadScoreColor(40), Colors.amber);
      expect(leadScoreColor(69), Colors.amber);
    });
    test('hot (>=70) is red', () {
      expect(leadScoreColor(70), Colors.red);
      expect(leadScoreColor(100), Colors.red);
    });
  });

  group('mission follow-up prioritization', () {
    test('prioritizes open mission leads by score', () {
      final leads = [
        _missionLead(id: 'cold', score: 20),
        _missionLead(id: 'hot', score: 90),
        _missionLead(id: 'warm', score: 55),
      ];

      final prioritized = prioritizedMissionFollowUpLeads(leads);

      expect(prioritized.map((lead) => lead.id), ['hot', 'warm', 'cold']);
    });

    test('excludes closed dead and completed follow-up leads', () {
      final leads = [
        _missionLead(id: 'open', score: 70),
        _missionLead(id: 'closed', score: 100, status: 'Closed'),
        _missionLead(id: 'dead', score: 99, status: 'Dead Lead'),
        _missionLead(id: 'done', score: 98, followUpStatus: 'Completed'),
      ];

      final prioritized = prioritizedMissionFollowUpLeads(leads);

      expect(prioritized.map((lead) => lead.id), ['open']);
    });

    test('summarizes next action from mission outcome', () {
      expect(
        missionNextActionSummary(
          leadCount: 0,
          priorityLeadCount: 0,
          areaRemainingEstimatedMinutes: 45,
        ),
        contains('No leads from this mission'),
      );
      expect(
        missionNextActionSummary(
          leadCount: 3,
          priorityLeadCount: 2,
          areaRemainingEstimatedMinutes: 45,
        ),
        contains('Review 2 open leads'),
      );
    });
  });

  group('mission stat safety', () {
    test('missionStreetTotal falls back to target street ids', () {
      final mission = Mission.fromMap({
        'id': 'm1',
        'drive_area_id': 'a1',
        'status': 'active',
        'target_street_ids': ['s1', 's2'],
        'street_count': 0,
      });

      expect(missionStreetTotalFor(mission), 2);
      expect(missionCoveredStreetCount(mission, {'s1'}), 1);
      expect(safePercent(1, 2), 50);
    });

    test('mission opportunity capture is clamped to a valid range', () {
      expect(
        safeMissionOpportunityCaptured(
          opportunityAtStart: 0,
          opportunityRemaining: 20,
        ),
        0,
      );
      expect(
        safeMissionOpportunityCaptured(
          opportunityAtStart: 100,
          opportunityRemaining: 120,
        ),
        0,
      );
      expect(
        safeMissionOpportunityCaptured(
          opportunityAtStart: 100,
          opportunityRemaining: -5,
        ),
        100,
      );
    });
  });

  group('lead display dedupe', () {
    test('dedupes imported parcel leads by parcel id', () {
      final leads = [
        _missionLead(
          id: 'low',
          score: 10,
          notes: 'Tulsa County parcel import\nParcel: 12345',
        ),
        _missionLead(
          id: 'high',
          score: 90,
          notes: 'Tulsa County parcel import\nParcel: 12345',
        ),
      ];

      final deduped = dedupeLeadsForDisplay(leads);

      expect(deduped, hasLength(1));
      expect(deduped.single.id, 'high');
    });

    test('dedupes manual leads by normalized address', () {
      final leads = [
        _missionLead(id: 'a', score: 10, address: '123 North Main Street'),
        _missionLead(id: 'b', score: 20, address: '123 n main st'),
      ];

      final deduped = dedupeLeadsForDisplay(leads);

      expect(deduped, hasLength(1));
      expect(deduped.single.id, 'b');
    });
  });

  group('route / mileage geo', () {
    final a = const LatLng(36.0, -95.0);
    final b = const LatLng(36.005, -95.0); // ~0.345 mi north of a (within gap)
    final c = const LatLng(36.030, -95.0); // ~1.7 mi north of b (exceeds gap)

    test('routeMiles is zero for empty or single point', () {
      expect(routeMiles([]), 0);
      expect(routeMiles([a]), 0);
    });

    test('routeMiles matches direct distance within a segment', () {
      final expected = const Distance().as(LengthUnit.Mile, a, b);
      expect(routeMiles([a, b]), closeTo(expected, 1e-6));
    });

    test('splitRouteSegments needs at least two points', () {
      expect(splitRouteSegments([]), isEmpty);
      expect(splitRouteSegments([a]), isEmpty);
    });

    test('splitRouteSegments breaks on a large gap and drops lone points', () {
      final segments = splitRouteSegments([a, b, c]);
      expect(segments.length, 1);
      expect(
        segments.first.length,
        2,
      ); // [a, b]; c starts a dropped 1-pt segment
    });

    test('pointToStreetSegmentMiles is ~0 on the segment start', () {
      expect(pointToStreetSegmentMiles(a, a, b), closeTo(0, 1e-6));
    });

    test('distanceToStreetMiles: empty path is infinite, on-path is ~0', () {
      const empty = CityStreet(
        id: '1',
        city: 'Tulsa',
        streetName: 'X',
        path: [],
      );
      final street = CityStreet(
        id: '2',
        city: 'Tulsa',
        streetName: 'Main',
        path: [a, b],
      );
      expect(distanceToStreetMiles(a, empty), double.infinity);
      expect(distanceToStreetMiles(a, street), closeTo(0, 1e-6));
    });
  });
}

Lead _missionLead({
  required String id,
  required int score,
  String status = 'New Lead',
  String followUpStatus = 'None',
  String address = '',
  String notes = '',
}) {
  return Lead.fromMap({
    'id': id,
    'address': address.isEmpty ? '$id Main St' : address,
    'condition': '',
    'notes': notes,
    'status': status,
    'source': 'Driving For Dollars',
    'lead_score': score,
    'follow_up_status': followUpStatus,
  });
}
