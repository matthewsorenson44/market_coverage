import 'dart:io';

void main(List<String> args) {
  final inputPath = _argValue(args, '--input');
  final outputPath = _argValue(args, '--output');

  if (inputPath == null || inputPath.isEmpty) {
    stderr.writeln(
      'Usage: dart run tool/import_market_cities.dart --input markets.csv '
      '[--output build/imports/market_cities_seed.sql]',
    );
    exitCode = 64;
    return;
  }

  final inputFile = File(inputPath);
  if (!inputFile.existsSync()) {
    stderr.writeln('Input CSV not found: $inputPath');
    exitCode = 66;
    return;
  }

  final rows = _readCsv(inputFile.readAsStringSync());
  if (rows.isEmpty) {
    stderr.writeln('CSV is empty.');
    exitCode = 65;
    return;
  }

  final headers = rows.first.map((header) => header.trim()).toList();
  final requiredHeaders = [
    'state_code',
    'state_name',
    'rank',
    'city',
    'population',
    'latitude',
    'longitude',
  ];
  final missingHeaders = requiredHeaders
      .where((header) => !headers.contains(header))
      .toList();
  if (missingHeaders.isNotEmpty) {
    stderr.writeln(
      'Missing required CSV columns: ${missingHeaders.join(', ')}',
    );
    exitCode = 65;
    return;
  }

  final values = <String>[];
  for (final row in rows.skip(1)) {
    if (row.every((cell) => cell.trim().isEmpty)) continue;

    final record = <String, String>{};
    for (var index = 0; index < headers.length; index++) {
      record[headers[index]] = index < row.length ? row[index].trim() : '';
    }

    final city = record['city'] ?? '';
    final stateCode = record['state_code'] ?? '';
    final stateName = record['state_name'] ?? '';
    if (city.isEmpty || stateCode.isEmpty || stateName.isEmpty) continue;

    values.add(
      '('
      '${_sqlString(city)}, '
      '${_sqlString(stateName)}, '
      '${_sqlString(stateCode.toUpperCase())}, '
      '${_sqlString('$city, ${stateCode.toUpperCase()}')}, '
      '${_sqlInt(record['rank'])}, '
      '${_sqlInt(record['population'])}, '
      '${_sqlDouble(record['latitude'])}, '
      '${_sqlDouble(record['longitude'])}, '
      "'planned'"
      ')',
    );
  }

  if (values.isEmpty) {
    stderr.writeln('No valid market rows found.');
    exitCode = 65;
    return;
  }

  final sql =
      '''
insert into market_cities (
  city,
  state,
  state_code,
  display_name,
  rank_in_state,
  population,
  latitude,
  longitude,
  market_status
)
values
${values.join(',\n')}
on conflict (city, state_code) do update set
  state = excluded.state,
  display_name = excluded.display_name,
  rank_in_state = excluded.rank_in_state,
  population = excluded.population,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  updated_at = now();
''';

  if (outputPath == null || outputPath.isEmpty) {
    stdout.write(sql);
    return;
  }

  final outputFile = File(outputPath);
  outputFile.parent.createSync(recursive: true);
  outputFile.writeAsStringSync(sql);
  stdout.writeln('Wrote ${values.length} market rows to $outputPath');
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _sqlString(String value) {
  return "'${value.replaceAll("'", "''")}'";
}

String _sqlInt(String? value) {
  final parsed = int.tryParse((value ?? '').replaceAll(',', '').trim());
  return parsed?.toString() ?? 'null';
}

String _sqlDouble(String? value) {
  final parsed = double.tryParse((value ?? '').trim());
  return parsed?.toString() ?? 'null';
}

List<List<String>> _readCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  final cell = StringBuffer();
  var inQuotes = false;

  for (var index = 0; index < input.length; index++) {
    final char = input[index];
    final next = index + 1 < input.length ? input[index + 1] : '';

    if (char == '"') {
      if (inQuotes && next == '"') {
        cell.write('"');
        index++;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char == ',' && !inQuotes) {
      row.add(cell.toString());
      cell.clear();
      continue;
    }

    if ((char == '\n' || char == '\r') && !inQuotes) {
      if (char == '\r' && next == '\n') index++;
      row.add(cell.toString());
      cell.clear();
      rows.add(row);
      row = <String>[];
      continue;
    }

    cell.write(char);
  }

  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }

  return rows;
}
