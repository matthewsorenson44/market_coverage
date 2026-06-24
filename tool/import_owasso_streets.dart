// Multi-county cities require bbox import, NOT county-name filtering.
// Known multi-county cities in Oklahoma:
//   Owasso:       Tulsa County + Rogers County
//   Broken Arrow: Tulsa County + Wagoner County
//   Tulsa:        Mostly Tulsa County (touches Rogers/Osage at edges)
//
// Usage:
//   dart run tool/import_owasso_streets.dart [city] [state] [north] [south] [east] [west]
//
// Examples:
//   dart run tool/import_owasso_streets.dart
//     (defaults: Owasso, OK, full city bbox)
//   dart run tool/import_owasso_streets.dart "Broken Arrow" OK 36.105 35.935 -95.715 -95.895
//   dart run tool/import_owasso_streets.dart "Tulsa" OK 36.225 35.960 -95.785 -96.070

import 'dart:convert';
import 'dart:io';

const overpassEndpoints = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
const sampleStreetIds = [
  'owasso-sim-route',
  'owasso-2nd-st-n',
  'owasso-main-st',
  'owasso-3rd-st-s',
];
const allowedHighways = {
  'primary',
  'secondary',
  'tertiary',
  'unclassified',
  'residential',
  'living_street',
  'service',
};
const excludedServices = {
  'alley',
  'driveway',
  'drive-through',
  'parking_aisle',
};

class ImportConfig {
  final String cityName;
  final String stateCode;
  final double north;
  final double south;
  final double east;
  final double west;
  final bool dryRun;
  final bool keepSampleRows;

  const ImportConfig({
    required this.cityName,
    required this.stateCode,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
    required this.dryRun,
    required this.keepSampleRows,
  });
}

Future<void> main(List<String> args) async {
  final config = parseImportConfig(args);
  final credentials = readSupabaseCredentials();

  stdout.writeln(
    'Fetching ${config.cityName} streets from OpenStreetMap bbox '
    'N:${config.north} S:${config.south} E:${config.east} W:${config.west}...',
  );

  final elements = await fetchOverpassElements(config);
  final streets = buildStreetRows(elements, config.cityName);

  stdout.writeln('Found ${streets.length} named drivable street segments.');

  if (streets.isEmpty) {
    stdout.writeln('No streets found. Nothing was imported.');
    exitCode = 1;
    return;
  }

  if (config.dryRun) {
    stdout.writeln('Dry run only. No Supabase rows were changed.');
    stdout.writeln('First 5 streets:');

    for (final street in streets.take(5)) {
      stdout.writeln('- ${street['street_name']} (${street['id']})');
    }

    return;
  }

  if (!config.keepSampleRows) {
    await deleteSampleRows(credentials);
  }

  final importedCount = await upsertStreetRows(credentials, streets);
  await updateMarketStreetStatus(
    credentials,
    cityName: config.cityName,
    stateCode: config.stateCode,
    streetCount: importedCount,
  );

  stdout.writeln('Import complete for ${config.cityName}.');
  stdout.writeln('Streets inserted: $importedCount');
  stdout.writeln('Now run in Supabase SQL Editor:');
  stdout.writeln(
    "  select recompute_market_readiness('${sqlLiteral(config.cityName)}', '${sqlLiteral(config.stateCode)}');",
  );
}

ImportConfig parseImportConfig(List<String> args) {
  final positional = args
      .where((arg) => !arg.startsWith('--'))
      .toList(growable: false);

  return ImportConfig(
    cityName: positional.isNotEmpty ? positional[0] : 'Owasso',
    stateCode: positional.length > 1 ? positional[1].toUpperCase() : 'OK',
    north: parseDoubleArg(positional, 2, 36.385),
    south: parseDoubleArg(positional, 3, 36.235),
    east: parseDoubleArg(positional, 4, -95.755),
    west: parseDoubleArg(positional, 5, -95.935),
    dryRun: args.contains('--dry-run'),
    keepSampleRows: args.contains('--keep-sample'),
  );
}

double parseDoubleArg(List<String> args, int index, double fallback) {
  if (args.length <= index) return fallback;

  return double.tryParse(args[index]) ?? fallback;
}

({String url, String apiKey, bool isServiceRole}) readSupabaseCredentials() {
  final mainFile = File('lib/main.dart');

  if (!mainFile.existsSync()) {
    throw StateError('Run this script from the project root.');
  }

  final source = mainFile.readAsStringSync();
  final urlMatch = RegExp(r"url:\s*'([^']+)'").firstMatch(source);
  final anonKeyMatch = RegExp(r"anonKey:\s*'([^']+)'").firstMatch(source);

  if (urlMatch == null || anonKeyMatch == null) {
    throw StateError('Could not find Supabase credentials in lib/main.dart.');
  }

  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  final apiKey = serviceRoleKey == null || serviceRoleKey.trim().isEmpty
      ? anonKeyMatch.group(1)!
      : serviceRoleKey.trim();

  return (
    url: urlMatch.group(1)!,
    apiKey: apiKey,
    isServiceRole: serviceRoleKey != null && serviceRoleKey.trim().isNotEmpty,
  );
}

Future<List<Map<String, dynamic>>> fetchOverpassElements(
  ImportConfig config,
) async {
  Object? lastError;

  for (final endpoint in overpassEndpoints) {
    try {
      final elements = await fetchFromOverpass(endpoint, config);

      if (elements.isNotEmpty) return elements;
    } catch (error) {
      lastError = error;
      stderr.writeln('Overpass endpoint failed: $endpoint');
    }
  }

  throw StateError('Could not fetch streets from Overpass. $lastError');
}

Future<List<Map<String, dynamic>>> fetchFromOverpass(
  String endpoint,
  ImportConfig config,
) async {
  final client = HttpClient();
  final request = await client.postUrl(Uri.parse(endpoint));

  request.headers.contentType = ContentType(
    'application',
    'x-www-form-urlencoded',
    charset: 'utf-8',
  );
  request.headers.set(
    HttpHeaders.userAgentHeader,
    'market_coverage street import',
  );
  request.write('data=${Uri.encodeQueryComponent(overpassQuery(config))}');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  client.close();

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final previewLength = body.length < 300 ? body.length : 300;

    throw HttpException(
      'Overpass returned ${response.statusCode}: ${body.substring(0, previewLength)}',
    );
  }

  final decoded = jsonDecode(body);
  final elements = decoded['elements'];

  if (elements is! List) return [];

  return elements.whereType<Map<String, dynamic>>().toList(growable: false);
}

String overpassQuery(ImportConfig config) =>
    '''
[out:json][timeout:90];
(
  way["highway"]["name"](${config.south},${config.west},${config.north},${config.east});
);
out geom;
''';

List<Map<String, dynamic>> buildStreetRows(
  List<Map<String, dynamic>> elements,
  String cityName,
) {
  final rowsById = <String, Map<String, dynamic>>{};
  final geometryHashes = <String>{};

  for (final element in elements) {
    final tags = element['tags'];
    final geometry = element['geometry'];

    if (tags is! Map || geometry is! List) continue;

    final highway = tags['highway']?.toString();
    final service = tags['service']?.toString();
    final streetName = tags['name']?.toString().trim();

    if (streetName == null || streetName.isEmpty) continue;
    if (!allowedHighways.contains(highway)) continue;
    if (highway == 'service' && excludedServices.contains(service)) continue;

    final path = geometry
        .whereType<Map>()
        .map(parseOverpassPoint)
        .whereType<Map<String, double>>()
        .toList(growable: false);

    if (path.length < 2) continue;

    final geometryHash = hashPath(path);
    if (!geometryHashes.add(geometryHash)) continue;

    final bounds = pathBounds(path);
    final id = 'osm-way-${element['id']}';
    rowsById[id] = {
      'id': id,
      'city': cityName,
      'street_name': streetName,
      'path': path,
      'min_lat': bounds.minLat,
      'max_lat': bounds.maxLat,
      'min_lng': bounds.minLng,
      'max_lng': bounds.maxLng,
    };
  }

  final rows = rowsById.values.toList(growable: false);

  rows.sort((a, b) {
    final firstName = a['street_name'].toString();
    final secondName = b['street_name'].toString();

    return firstName.compareTo(secondName);
  });

  return rows;
}

Map<String, double>? parseOverpassPoint(Map point) {
  final lat = parseDouble(point['lat']);
  final lng = parseDouble(point['lon']);

  if (lat == null || lng == null) return null;

  return {'lat': lat, 'lng': lng};
}

double? parseDouble(dynamic value) {
  if (value is num) return value.toDouble();

  return double.tryParse(value?.toString() ?? '');
}

String hashPath(List<Map<String, double>> path) {
  return path
      .map(
        (point) =>
            '${point['lat']!.toStringAsFixed(7)},${point['lng']!.toStringAsFixed(7)}',
      )
      .join('|');
}

({double minLat, double maxLat, double minLng, double maxLng}) pathBounds(
  List<Map<String, double>> path,
) {
  var minLat = path.first['lat']!;
  var maxLat = path.first['lat']!;
  var minLng = path.first['lng']!;
  var maxLng = path.first['lng']!;

  for (final point in path.skip(1)) {
    final lat = point['lat']!;
    final lng = point['lng']!;

    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }

  return (minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng);
}

Future<void> deleteSampleRows(
  ({String url, String apiKey, bool isServiceRole}) credentials,
) async {
  final filter = Uri.encodeQueryComponent('in.(${sampleStreetIds.join(',')})');
  final uri = Uri.parse('${credentials.url}/rest/v1/city_streets?id=$filter');
  final response = await sendSupabaseRequest(
    credentials,
    method: 'DELETE',
    uri: uri,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Could not delete sample streets: ${response.statusCode} ${response.body}',
    );
  }
}

Future<int> upsertStreetRows(
  ({String url, String apiKey, bool isServiceRole}) credentials,
  List<Map<String, dynamic>> streets,
) async {
  const batchSize = 100;
  var importedCount = 0;

  for (var start = 0; start < streets.length; start += batchSize) {
    final end = start + batchSize > streets.length
        ? streets.length
        : start + batchSize;
    final batch = streets.sublist(start, end);
    final uri = Uri.parse(
      '${credentials.url}/rest/v1/city_streets?on_conflict=id',
    );
    final response = await sendSupabaseRequest(
      credentials,
      method: 'POST',
      uri: uri,
      body: jsonEncode(batch),
      extraHeaders: const {
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 && !credentials.isServiceRole) {
        throw StateError(
          'Supabase rejected the import because Row Level Security blocks the anon key. '
          'Set SUPABASE_SERVICE_ROLE_KEY in PowerShell and run the import again.',
        );
      }

      throw HttpException(
        'Could not import street batch: ${response.statusCode} ${response.body}',
      );
    }

    importedCount = end;
    stdout.writeln('Imported $importedCount / ${streets.length}');
  }

  return importedCount;
}

Future<void> updateMarketStreetStatus(
  ({String url, String apiKey, bool isServiceRole}) credentials, {
  required String cityName,
  required String stateCode,
  required int streetCount,
}) async {
  final cityFilter = Uri.encodeQueryComponent('eq.$cityName');
  final stateFilter = Uri.encodeQueryComponent('eq.$stateCode');
  final uri = Uri.parse(
    '${credentials.url}/rest/v1/markets?city=$cityFilter&state_code=$stateFilter',
  );
  final response = await sendSupabaseRequest(
    credentials,
    method: 'PATCH',
    uri: uri,
    body: jsonEncode({
      'street_data_status': streetCount >= 500 ? 'complete' : 'partial',
      'cached_street_count': streetCount,
      'streets_last_imported_at': DateTime.now().toUtc().toIso8601String(),
    }),
    extraHeaders: const {'Prefer': 'return=minimal'},
  );

  if (response.statusCode >= 200 && response.statusCode < 300) return;

  if (response.statusCode == 404 || response.body.contains('does not exist')) {
    stdout.writeln(
      'Skipped markets update because the markets table/row was not found.',
    );
    return;
  }

  throw HttpException(
    'Could not update markets row: ${response.statusCode} ${response.body}',
  );
}

Future<({int statusCode, String body})> sendSupabaseRequest(
  ({String url, String apiKey, bool isServiceRole}) credentials, {
  required String method,
  required Uri uri,
  String? body,
  Map<String, String> extraHeaders = const {},
}) async {
  final client = HttpClient();
  final request = await client.openUrl(method, uri);

  request.headers.set('apikey', credentials.apiKey);
  request.headers.set('Authorization', 'Bearer ${credentials.apiKey}');
  request.headers.contentType = ContentType.json;

  for (final header in extraHeaders.entries) {
    request.headers.set(header.key, header.value);
  }

  if (body != null) {
    request.write(body);
  }

  final response = await request.close();
  final responseBody = await response.transform(utf8.decoder).join();

  client.close();

  return (statusCode: response.statusCode, body: responseBody);
}

String sqlLiteral(String value) => value.replaceAll("'", "''");
