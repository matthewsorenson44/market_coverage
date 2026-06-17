/// Pure formatting, parsing, and date helpers with no Flutter or package
/// dependencies. Kept dependency-free so they're trivially unit-testable.
library;

DateTime? parseDateOnly(dynamic value) {
  if (value == null) return null;

  final parsedDate = DateTime.tryParse(value.toString());

  if (parsedDate == null) return null;

  return DateTime(parsedDate.year, parsedDate.month, parsedDate.day);
}

String? formatDateOnly(DateTime? date) {
  if (date == null) return null;

  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');

  return '$year-$month-$day';
}

String displayDate(DateTime? date) {
  if (date == null) return 'Not set';

  return formatDateOnly(date) ?? 'Not set';
}

String formatMoney(double? value) {
  if (value == null) return 'Not set';

  final roundedValue = value.round();
  final sign = roundedValue < 0 ? '-' : '';
  final digits = roundedValue.abs().toString();
  final buffer = StringBuffer();

  for (var index = 0; index < digits.length; index++) {
    final remainingDigits = digits.length - index;

    buffer.write(digits[index]);

    if (remainingDigits > 1 && remainingDigits % 3 == 1) {
      buffer.write(',');
    }
  }

  return '$sign\$${buffer.toString()}';
}

DateTime todayDateOnly() {
  final now = DateTime.now();

  return DateTime(now.year, now.month, now.day);
}

DateTime startOfCurrentWeek() {
  final today = todayDateOnly();

  return today.subtract(Duration(days: today.weekday - DateTime.monday));
}

bool isSameDate(DateTime? firstDate, DateTime secondDate) {
  if (firstDate == null) return false;

  return firstDate.year == secondDate.year &&
      firstDate.month == secondDate.month &&
      firstDate.day == secondDate.day;
}

bool isBeforeDate(DateTime? firstDate, DateTime secondDate) {
  if (firstDate == null) return false;

  return DateTime(
    firstDate.year,
    firstDate.month,
    firstDate.day,
  ).isBefore(secondDate);
}

String? cleanParcelText(dynamic value) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty) return null;

  return text;
}

double? parseParcelDouble(dynamic value) {
  if (value is num) return value.toDouble();

  return double.tryParse(value?.toString() ?? '');
}

int? parseParcelInt(dynamic value) {
  if (value is num) return value.toInt();

  return int.tryParse(value?.toString() ?? '');
}

double? firstParcelDouble(List<dynamic> values) {
  for (final value in values) {
    final parsedValue = parseParcelDouble(value);

    if (parsedValue != null && parsedValue > 0) return parsedValue;
  }

  return null;
}

String formatDecimal(double? value) {
  if (value == null) return 'Not set';

  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }

  return value.toStringAsFixed(2);
}

String? combineMailingAddress(Map<String, dynamic> attributes) {
  final line1 = cleanParcelText(attributes['Address1']);
  final line2 = cleanParcelText(attributes['Address2']);
  final city = cleanParcelText(attributes['City']);
  final state = cleanParcelText(attributes['State']);
  final zip = cleanParcelText(attributes['ZIPCode']);
  final cityStateZip = [?city, ?state, ?zip].join(', ');
  final rows = [?line1, ?line2, if (cityStateZip.isNotEmpty) cityStateZip];

  if (rows.isEmpty) return null;

  return rows.join('\n');
}

String normalizedAddressKey(String? address) {
  if (address == null) return '';

  return address
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .replaceAll('AVENUE', 'AVE')
      .replaceAll('STREET', 'ST')
      .replaceAll('NORTH', 'N')
      .replaceAll('SOUTH', 'S')
      .replaceAll('EAST', 'E')
      .replaceAll('WEST', 'W');
}

String? houseNumberFromAddress(String? address) {
  if (address == null) return null;

  final match = RegExp(r'^\s*([0-9]+[A-Z]?)\b').firstMatch(address);

  return match?.group(1);
}

double? parseCoordinate(dynamic value) {
  if (value is num) return value.toDouble();

  return double.tryParse(value?.toString() ?? '');
}
