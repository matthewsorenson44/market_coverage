// Unit tests for the smart distressed-seller scoring model.
//
// Run just these with:  flutter test test/lead_score_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:market_coverage/main.dart';

void main() {
  // Fixed "now" so tenure-based assertions are deterministic.
  final now = DateTime(2026, 6, 16);

  group('calculateSmartLeadScore', () {
    test('jackpot stack scores 82 (vacant + roof + broken + records)', () {
      final score = calculateSmartLeadScore(
        vacantAppearance: true, // 16
        roofDamage: true, // 12
        trashInYard: false,
        brokenWindows: true, // 9
        tallGrass: false,
        outOfStateOwner: true, // 14
        lastSaleDate: '2002-01-01', // ~24 yrs -> 18
        assessedValue: 135000, // sweet spot -> 13
        now: now,
      );

      expect(score, 82);
    });

    test('all signals on clamps to exactly 100', () {
      final score = calculateSmartLeadScore(
        vacantAppearance: true,
        roofDamage: true,
        trashInYard: true,
        brokenWindows: true,
        tallGrass: true,
        outOfStateOwner: true,
        lastSaleDate: '2000-01-01',
        assessedValue: 120000,
        now: now,
      );

      expect(score, 100);
    });

    test('missing records falls back to condition-only (graceful)', () {
      final score = calculateSmartLeadScore(
        vacantAppearance: true, // 16
        roofDamage: true, // 12
        trashInYard: false,
        brokenWindows: false,
        tallGrass: false,
        // No records at all.
        now: now,
      );

      expect(score, 28);
    });

    test('high-end assessed value is penalized vs sweet spot', () {
      int withValue(double v) => calculateSmartLeadScore(
        vacantAppearance: true, // 16
        roofDamage: false,
        trashInYard: false,
        brokenWindows: false,
        tallGrass: false,
        assessedValue: v,
        now: now,
      );

      expect(withValue(135000), 29); // 16 + 13
      expect(withValue(600000), 18); // 16 + 2
    });

    group('years-owned tenure tiers', () {
      int withSale(String date) => calculateSmartLeadScore(
        vacantAppearance: true, // 16 baseline
        roofDamage: false,
        trashInYard: false,
        brokenWindows: false,
        tallGrass: false,
        lastSaleDate: date,
        now: now,
      );

      test('20+ years -> +18', () => expect(withSale('2002-01-01'), 34));
      test('10-19 years -> +14', () => expect(withSale('2014-01-01'), 30));
      test('4-9 years -> +8', () => expect(withSale('2020-01-01'), 24));
      test('0-3 years (recent buyer) -> +2', () {
        expect(withSale('2025-06-01'), 18);
      });
      test('unknown sale date -> +0', () => expect(withSale(''), 16));
    });

    group('out-of-state / absentee credit', () {
      test('out-of-state owner -> +14', () {
        final score = calculateSmartLeadScore(
          vacantAppearance: true, // 16
          roofDamage: false,
          trashInYard: false,
          brokenWindows: false,
          tallGrass: false,
          outOfStateOwner: true,
          now: now,
        );
        expect(score, 30);
      });

      test('in-state absentee (mailing != property) -> +9', () {
        final score = calculateSmartLeadScore(
          vacantAppearance: true, // 16
          roofDamage: false,
          trashInYard: false,
          brokenWindows: false,
          tallGrass: false,
          mailingAddress: 'PO Box 5, Dallas TX',
          propertyAddress: '123 Main St, Tulsa OK',
          now: now,
        );
        expect(score, 25);
      });

      test('owner-occupant (mailing == property) -> +0', () {
        final score = calculateSmartLeadScore(
          vacantAppearance: true, // 16
          roofDamage: false,
          trashInYard: false,
          brokenWindows: false,
          tallGrass: false,
          mailingAddress: '123 Main Street',
          propertyAddress: '123 Main St',
          now: now,
        );
        expect(score, 16);
      });
    });
  });

  group('yearsOwnedFromSaleDate', () {
    test('null and empty return null', () {
      expect(yearsOwnedFromSaleDate(null, now), isNull);
      expect(yearsOwnedFromSaleDate('', now), isNull);
      expect(yearsOwnedFromSaleDate('   ', now), isNull);
    });

    test('ISO date parses to whole years', () {
      expect(yearsOwnedFromSaleDate('2002-01-01', now), 24);
    });

    test('bare 4-digit year parses', () {
      expect(yearsOwnedFromSaleDate('1998', now), 28);
    });

    test('epoch milliseconds string parses', () {
      final ms = DateTime(2010, 1, 1).millisecondsSinceEpoch.toString();
      expect(yearsOwnedFromSaleDate(ms, now), 16);
    });

    test('unparseable text returns null', () {
      expect(yearsOwnedFromSaleDate('not a date', now), isNull);
    });

    test('future sale date returns null', () {
      expect(yearsOwnedFromSaleDate('2030-01-01', now), isNull);
    });
  });
}
