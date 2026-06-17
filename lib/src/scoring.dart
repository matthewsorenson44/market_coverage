/// Lead pipeline stages and the smart distressed-seller scoring model, plus the
/// small badge widgets that visualize a score/stage.
library;

import 'package:flutter/material.dart';

import 'formatting.dart';

const List<String> leadStatusOptions = [
  'New Lead',
  'Contact Needed',
  'Contacted',
  'Interested',
  'Offer Sent',
  'Under Contract',
  'Closed',
  'Dead Lead',
];

String normalizeLeadStage(String status) {
  switch (status) {
    case 'New':
      return 'New Lead';
    case 'Follow Up':
      return 'Contact Needed';
    case 'Offer Made':
      return 'Offer Sent';
    case 'Dead':
      return 'Dead Lead';
    default:
      return leadStatusOptions.contains(status) ? status : 'New Lead';
  }
}

/// Years a parcel has been owned, derived from a stored last-sale-date string.
///
/// Returns null when no usable date can be parsed (blank, unknown, or
/// un-enriched lead) so the caller can treat tenure as "unknown" rather than
/// guessing.
int? yearsOwnedFromSaleDate(String? lastSaleDate, DateTime now) {
  if (lastSaleDate == null) return null;

  final raw = lastSaleDate.trim();
  if (raw.isEmpty) return null;

  DateTime? saleDate = DateTime.tryParse(raw);

  if (saleDate == null) {
    // ArcGIS / county feeds sometimes return epoch milliseconds as a string.
    final asInt = int.tryParse(raw);
    if (asInt != null && asInt > 100000000000) {
      saleDate = DateTime.fromMillisecondsSinceEpoch(asInt);
    }
  }

  if (saleDate == null) {
    // Fall back to a bare 4-digit year anywhere in the string.
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(raw);
    if (yearMatch != null) {
      final year = int.tryParse(yearMatch.group(0)!);
      if (year != null) saleDate = DateTime(year, 1, 1);
    }
  }

  if (saleDate == null) return null;

  final years = now.difference(saleDate).inDays ~/ 365;
  if (years < 0 || years > 200) return null;

  return years;
}

/// Smart distressed-seller score (0-100).
///
/// Two pillars:
///  - Property distress (field-observed condition): up to 55 pts.
///  - Owner motivation & deal-fit (public records): up to 45 pts.
///
/// Every records signal is optional. When its data is missing it contributes
/// 0, so a freshly captured lead with no parcel data scores on condition alone
/// (max 55) and climbs toward "hot" as records get enriched.
int calculateSmartLeadScore({
  // Field-observed condition.
  required bool vacantAppearance,
  required bool roofDamage,
  required bool trashInYard,
  required bool brokenWindows,
  required bool tallGrass,
  // Public records (all optional).
  bool outOfStateOwner = false,
  String? mailingAddress,
  String? propertyAddress,
  String? lastSaleDate,
  double? assessedValue,
  DateTime? now,
}) {
  var score = 0;

  // --- Pillar A: property distress (max 55) ---
  // Strongest direct evidence the owner has stopped paying or caring.
  if (vacantAppearance) score += 16; // top motivation signal
  if (roofDamage) score += 12; // expensive deferred maintenance
  if (trashInYard) score += 10; // abandonment / eviction / code pressure
  if (brokenWindows) score += 9; // vacancy / vandalism correlate
  if (tallGrass) score += 8; // weakest, noisiest signal

  // --- Pillar B: owner motivation & deal-fit (max 45) ---

  // Years owned (max 18) — proxy for equity and owner life stage. Derived from
  // the last sale date; very recent purchases stay near the floor.
  final yearsOwned = yearsOwnedFromSaleDate(
    lastSaleDate,
    now ?? DateTime.now(),
  );
  if (yearsOwned != null) {
    if (yearsOwned >= 20) {
      score += 18; // max equity, oldest owners, prime estate/burnout
    } else if (yearsOwned >= 10) {
      score += 14;
    } else if (yearsOwned >= 4) {
      score += 8;
    } else {
      score += 2; // 0-3 yrs: recent buyer, thin equity
    }
  }

  // Out-of-state / absentee owner (max 14) — no emotional attachment, costly to
  // manage remotely; highest-converting wholesale segment.
  if (outOfStateOwner) {
    score += 14;
  } else {
    final mailKey = normalizedAddressKey(mailingAddress);
    final propKey = normalizedAddressKey(propertyAddress);
    if (mailKey.isNotEmpty && propKey.isNotEmpty && mailKey != propKey) {
      score += 9; // in-state absentee (mailing address differs from property)
    }
  }

  // Assessed value (max 13) — deal-fit band, not distress. Rewards the
  // wholesale sweet spot and penalizes high-end, hard-to-assign homes.
  if (assessedValue != null) {
    if (assessedValue >= 50000 && assessedValue <= 200000) {
      score += 13; // classic wholesale range
    } else if (assessedValue < 50000) {
      score += 7; // cheap spread but war-zone / teardown risk
    } else if (assessedValue <= 350000) {
      score += 7; // workable, thinner investor demand
    } else {
      score += 2; // high-end: few cash buyers, harder assignment
    }
  }

  return score.clamp(0, 100);
}

Color leadScoreColor(int score) {
  if (score >= 70) return Colors.red;
  if (score >= 40) return Colors.amber;
  return Colors.green;
}

Widget leadScoreBadge(int score, {double fontSize = 16}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: leadScoreColor(score),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$score',
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Color leadStatusColor(String status) {
  switch (normalizeLeadStage(status)) {
    case 'Contact Needed':
      return Colors.amber;
    case 'Contacted':
      return Colors.orange;
    case 'Interested':
      return Colors.teal;
    case 'Offer Sent':
      return Colors.blue;
    case 'Under Contract':
      return Colors.purple;
    case 'Closed':
      return Colors.green;
    case 'Dead Lead':
      return Colors.grey;
    case 'New Lead':
    default:
      return Colors.red;
  }
}

Widget leadStageBadge(String status) {
  final stage = normalizeLeadStage(status);

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: leadStatusColor(stage),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      stage,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}
