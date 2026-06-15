import 'dart:convert';
import 'dart:io';

const cityName = 'Owasso';
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

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final keepSampleRows = args.contains('--keep-sample');
  final credentials = readSupabaseCredentials();

  stdout.writeln('Fetching $cityName streets from OpenStreetMap...');

  final elements = await fetchOverpassElements();
  final streets = buildStreetRows(elements);

  stdout.writeln('Found ${streets.length} named drivable street segments.');

  if (streets.isEmpty) {
    stdout.writeln('No streets found. Nothing was imported.');
    exitCode = 1;
    return;
  }

  if (dryRun) {
    stdout.writeln('Dry run only. No Supabase rows were changed.');
    stdout.writeln('First 5 streets:');

    for (final street in streets.take(5)) {
      stdout.writeln('- ${street['street_name']} (${street['id']})');
    }

    return;
  }

  if (!keepSampleRows) {
    await deleteSampleRows(credentials);
  }

  await upsertStreetRows(credentials, streets);

  stdout.writeln('Imported ${streets.length} $cityName street segments.');
}

({String url, String anonKey}) readSupabaseCredentials() {
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

  return (url: urlMatch.group(1)!, anonKey: anonKeyMatch.group(1)!);
}

Future<List<Map<String, dynamic>>> fetchOverpassElements() async {
  Object? lastError;

  for (final endpoint in overpassEndpoints) {
    try {
      final elements = await fetchFromOverpass(endpoint);

      if (elements.isNotEmpty) return elements;
    } catch (error) {
      lastError = error;
      stderr.writeln('Overpass endpoint failed: $endpoint');
    }
  }

  throw StateError('Could not fetch streets from Overpass. $lastError');
}

Future<List<Map<String, dynamic>>> fetchFromOverpass(String endpoint) async {
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
  request.write('data=${Uri.encodeQueryComponent(overpassQuery)}');

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  client.close();

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException(
      'Overpass returned ${response.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}',
    );
  }

  final decoded = jsonDecode(body);
  final elements = decoded['elements'];

  if (elements is! List) return [];

  return elements.whereType<Map<String, dynamic>>().toList(growable: false);
}

const overpassQuery = '''
[out:json][timeout:90];
area["name"="Owasso"]["boundary"="administrative"]["admin_level"="8"]->.searchArea;
(
  way(area.searchArea)["highway"]["name"];
);
out geom;
''';

List<Map<String, dynamic>> buildStreetRows(
  List<Map<String, dynamic>> elements,
) {
  final rowsById = <String, Map<String, dynamic>>{};

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
        .map((point) => {'lat': point['lat'], 'lng': point['lon']})
        .where((point) => point['lat'] != null && point['lng'] != null)
        .toList(growable: false);

    if (path.length < 2) continue;

    rowsById['osm-way-${element['id']}'] = {
      'id': 'osm-way-${element['id']}',
      'city': cityName,
      'street_name': streetName,
      'path': path,
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

Future<void> deleteSampleRows(
  ({String url, String anonKey}) credentials,
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

Future<void> upsertStreetRows(
  ({String url, String anonKey}) credentials,
  List<Map<String, dynamic>> streets,
) async {
  const batchSize = 100;

  for (var start = 0; start < streets.length; start += batchSize) {
    final end = (start + batchSize).clamp(0, streets.length);
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
      throw HttpException(
        'Could not import street batch: ${response.statusCode} ${response.body}',
      );
    }

    stdout.writeln(
      'Imported ${end.clamp(0, streets.length)} / ${streets.length}',
    );
  }
}

Future<({int statusCode, String body})> sendSupabaseRequest(
  ({String url, String anonKey}) credentials, {
  required String method,
  required Uri uri,
  String? body,
  Map<String, String> extraHeaders = const {},
}) async {
  final client = HttpClient();
  final request = await client.openUrl(method, uri);

  request.headers.set('apikey', credentials.anonKey);
  request.headers.set('Authorization', 'Bearer ${credentials.anonKey}');
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
