import 'dart:convert';
import 'dart:io';

const defaultArcGisOutFields = [
  'OBJECTID',
  'FullName',
  'Label',
  'City_L',
  'City_R',
];

const streetNameFields = [
  'FullName',
  'Label',
  'LgcyFullName',
  'AltStName1',
  'name',
  'NAME',
  'street_name',
];

const idFields = ['NGUID_RDCL', 'LINK_ID', 'INCOGID', 'OBJECTID', 'id', 'ID'];

const arcGisPageSize = 250;

Future<void> main(List<String> args) async {
  if (hasFlag(args, '--help') || args.isEmpty) {
    writeUsage();
    return;
  }

  final city = readRequiredOption(args, '--city');
  final inputPath = readOption(args, '--input');
  final arcGisUrl = readOption(args, '--arcgis-url');
  final where = readOption(args, '--where') ?? '1=1';
  final outputPath =
      readOption(args, '--output') ??
      'build/imports/${slugify(city)}_city_streets.csv';
  final shouldUpload = hasFlag(args, '--upload');
  final dryRun = hasFlag(args, '--dry-run');

  if (inputPath == null && arcGisUrl == null) {
    throw ArgumentError('Pass either --input or --arcgis-url.');
  }

  if (inputPath != null && arcGisUrl != null) {
    throw ArgumentError('Use --input or --arcgis-url, not both.');
  }

  final features = inputPath == null
      ? await fetchArcGisFeatures(arcGisUrl!, where)
      : readGeoJsonFeatures(File(inputPath));
  final rows = buildStreetRows(city, features);

  stdout.writeln('Read ${features.length} GeoJSON features.');
  stdout.writeln('Built ${rows.length} city_streets rows for $city.');

  if (rows.isEmpty) {
    stdout.writeln('No valid named LineString rows found. Nothing to import.');
    exitCode = 1;
    return;
  }

  stdout.writeln('First 5 rows:');
  for (final row in rows.take(5)) {
    stdout.writeln('- ${row.id}: ${row.streetName} (${row.path.length} pts)');
  }

  if (!dryRun) {
    writeCsv(outputPath, rows);
    stdout.writeln('Wrote $outputPath');
  }

  if (shouldUpload) {
    await uploadRows(rows);
  } else {
    stdout.writeln('Dry conversion only. Add --upload to upsert to Supabase.');
  }
}

List<Map<String, dynamic>> readGeoJsonFeatures(File file) {
  if (!file.existsSync()) {
    throw ArgumentError('GeoJSON file not found: ${file.path}');
  }

  final decoded = jsonDecode(file.readAsStringSync());

  return featuresFromGeoJson(decoded);
}

Future<List<Map<String, dynamic>>> fetchArcGisFeatures(
  String arcGisUrl,
  String where,
) async {
  final features = <Map<String, dynamic>>[];
  final client = HttpClient();

  try {
    for (var offset = 0; ; offset += arcGisPageSize) {
      final uri = Uri.parse(arcGisUrl).replace(
        queryParameters: {
          'f': 'json',
          'where': where,
          'outFields': defaultArcGisOutFields.join(','),
          'returnGeometry': 'true',
          'outSR': '4326',
          'resultOffset': offset.toString(),
          'resultRecordCount': arcGisPageSize.toString(),
        },
      );
      final body = await httpGet(client, uri);
      final pageFeatures = featuresFromArcGisJson(jsonDecode(body));

      if (pageFeatures.isEmpty) break;

      features.addAll(pageFeatures);
      stdout.writeln('Fetched ${features.length} features...');

      if (pageFeatures.length < arcGisPageSize) break;
    }
  } finally {
    client.close(force: true);
  }

  return features;
}

List<Map<String, dynamic>> featuresFromArcGisJson(dynamic decoded) {
  if (decoded is! Map) return [];

  final error = decoded['error'];

  if (error is Map) {
    throw FormatException('ArcGIS error: ${jsonEncode(error)}');
  }

  final features = decoded['features'];

  if (features is! List) return [];

  return features
      .whereType<Map>()
      .map((feature) {
        final attributes =
            (feature['attributes'] as Map?)?.cast<String, dynamic>() ?? {};
        final geometry = (feature['geometry'] as Map?)?.cast<String, dynamic>();
        final paths = geometry?['paths'];
        final coordinates = paths is List && paths.length == 1
            ? paths.first
            : paths;

        return {
          'type': 'Feature',
          'properties': attributes,
          'geometry': {
            'type': paths is List && paths.length == 1
                ? 'LineString'
                : 'MultiLineString',
            'coordinates': coordinates,
          },
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> featuresFromGeoJson(dynamic decoded) {
  if (decoded is! Map) return [];

  final error = decoded['error'];

  if (error is Map) {
    throw FormatException('ArcGIS error: ${jsonEncode(error)}');
  }

  final type = decoded['type']?.toString();

  if (type == 'Feature') {
    return [decoded.cast<String, dynamic>()];
  }

  final features = decoded['features'];

  if (type != 'FeatureCollection' || features is! List) return [];

  return features
      .whereType<Map>()
      .map((feature) => feature.cast<String, dynamic>())
      .toList(growable: false);
}

List<StreetRow> buildStreetRows(
  String city,
  List<Map<String, dynamic>> features,
) {
  final rowsById = <String, StreetRow>{};

  for (var featureIndex = 0; featureIndex < features.length; featureIndex++) {
    final feature = features[featureIndex];
    final properties =
        (feature['properties'] as Map?)?.cast<String, dynamic>() ?? {};
    final geometry = (feature['geometry'] as Map?)?.cast<String, dynamic>();
    final streetName = readStreetName(properties);

    if (geometry == null || streetName == null) continue;

    final paths = readGeometryPaths(geometry);
    final sourceId = readSourceId(properties) ?? 'feature-${featureIndex + 1}';

    for (var pathIndex = 0; pathIndex < paths.length; pathIndex++) {
      final path = paths[pathIndex];

      if (path.length < 2) continue;

      final idSuffix = paths.length == 1 ? '' : '-part-${pathIndex + 1}';
      final id = '${slugify(city)}-${slugify(sourceId)}$idSuffix';
      rowsById[id] = StreetRow(
        id: id,
        city: city,
        streetName: streetName,
        path: path,
      );
    }
  }

  final rows = rowsById.values.toList(growable: false);

  rows.sort((a, b) {
    final cityCompare = a.city.compareTo(b.city);

    if (cityCompare != 0) return cityCompare;

    final nameCompare = a.streetName.compareTo(b.streetName);

    if (nameCompare != 0) return nameCompare;

    return a.id.compareTo(b.id);
  });

  return rows;
}

String? readStreetName(Map<String, dynamic> properties) {
  for (final field in streetNameFields) {
    final value = cleanText(properties[field]);

    if (value != null) return value;
  }

  final parts = [
    cleanText(properties['PreDir']),
    cleanText(properties['Street']),
    cleanText(properties['StreetType']),
    cleanText(properties['SufDir']),
  ].whereType<String>().toList(growable: false);

  if (parts.isEmpty) return null;

  return parts.join(' ');
}

String? readSourceId(Map<String, dynamic> properties) {
  for (final field in idFields) {
    final value = cleanText(properties[field]);

    if (value != null) return value;
  }

  return null;
}

String? cleanText(dynamic value) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty || text.toLowerCase() == 'null') {
    return null;
  }

  return text;
}

List<List<StreetPoint>> readGeometryPaths(Map<String, dynamic> geometry) {
  final type = geometry['type']?.toString();
  final coordinates = geometry['coordinates'];

  if (type == 'LineString' && coordinates is List) {
    return [readLineString(coordinates)];
  }

  if (type == 'MultiLineString' && coordinates is List) {
    return coordinates
        .whereType<List>()
        .map(readLineString)
        .where((path) => path.length >= 2)
        .toList(growable: false);
  }

  return [];
}

List<StreetPoint> readLineString(List<dynamic> coordinates) {
  return coordinates
      .map(readCoordinate)
      .whereType<StreetPoint>()
      .toList(growable: false);
}

StreetPoint? readCoordinate(dynamic value) {
  if (value is! List || value.length < 2) return null;

  final longitude = readDouble(value[0]);
  final latitude = readDouble(value[1]);

  if (latitude == null || longitude == null) return null;
  if (latitude < -90 || latitude > 90) return null;
  if (longitude < -180 || longitude > 180) return null;

  return StreetPoint(latitude: latitude, longitude: longitude);
}

double? readDouble(dynamic value) {
  if (value is num) return value.toDouble();

  return double.tryParse(value?.toString() ?? '');
}

void writeCsv(String outputPath, List<StreetRow> rows) {
  final file = File(outputPath);

  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    [
      [
        'id',
        'city',
        'street_name',
        'path',
        'min_lat',
        'max_lat',
        'min_lng',
        'max_lng',
      ].join(','),
      ...rows.map((row) => row.toCsvLine()),
    ].join('\n'),
  );
}

Future<void> uploadRows(List<StreetRow> rows) async {
  final url = Platform.environment['SUPABASE_URL'];
  final serviceRoleKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];

  if (url == null || url.isEmpty) {
    throw StateError('Set SUPABASE_URL before using --upload.');
  }

  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    throw StateError('Set SUPABASE_SERVICE_ROLE_KEY before using --upload.');
  }

  const batchSize = 250;
  final client = HttpClient();

  try {
    for (var start = 0; start < rows.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, rows.length);
      final batch = rows.sublist(start, end);
      final uri = Uri.parse('$url/rest/v1/city_streets?on_conflict=id');
      final request = await client.postUrl(uri);

      request.headers.contentType = ContentType.json;
      request.headers.set('apikey', serviceRoleKey);
      request.headers.set('Authorization', 'Bearer $serviceRoleKey');
      request.headers.set(
        'Prefer',
        'resolution=merge-duplicates,return=minimal',
      );
      request.write(jsonEncode(batch.map((row) => row.toJson()).toList()));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Supabase upload failed: ${response.statusCode} $body',
        );
      }

      stdout.writeln('Uploaded $end / ${rows.length}');
    }
  } finally {
    client.close(force: true);
  }
}

Future<String> httpGet(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri);

  request.headers.set(
    HttpHeaders.userAgentHeader,
    'market_coverage street import',
  );

  final response = await request.close();
  final body = await response.transform(utf8.decoder).join();

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw HttpException('GET failed: ${response.statusCode} $body', uri: uri);
  }

  return body;
}

String readRequiredOption(List<String> args, String name) {
  final value = readOption(args, name);

  if (value == null || value.isEmpty) {
    throw ArgumentError('Missing required option: $name');
  }

  return value;
}

String? readOption(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];

    if (arg == name && index + 1 < args.length) {
      return args[index + 1];
    }

    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }

  return null;
}

bool hasFlag(List<String> args, String name) {
  return args.contains(name);
}

String slugify(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  return slug.isEmpty ? 'street' : slug;
}

void writeUsage() {
  stdout.writeln('''
Import real street centerline GeoJSON into city_streets.

Required:
  --city <name>

Input, choose one:
  --input <file.geojson>
  --arcgis-url <FeatureServer layer query URL> --where <SQL where>

Optional:
  --output <file.csv>   Defaults to build/imports/<city>_city_streets.csv
  --dry-run             Parse and summarize without writing CSV
  --upload              Upsert to Supabase using environment credentials

Upload environment:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY

Example:
  dart run tool/import_city_streets_geojson.dart --city Tulsa --arcgis-url https://map11.incog.org/arcgis11wa/rest/services/RoadCenterlines_updated/FeatureServer/0/query --where "City_L = 'TULSA' OR City_R = 'TULSA'" --dry-run
''');
}

class StreetPoint {
  final double latitude;
  final double longitude;

  const StreetPoint({required this.latitude, required this.longitude});

  Map<String, double> toJson() {
    return {'lat': latitude, 'lng': longitude};
  }
}

class StreetRow {
  final String id;
  final String city;
  final String streetName;
  final List<StreetPoint> path;

  const StreetRow({
    required this.id,
    required this.city,
    required this.streetName,
    required this.path,
  });

  double get minLat {
    return path.map((point) => point.latitude).reduce((a, b) => a < b ? a : b);
  }

  double get maxLat {
    return path.map((point) => point.latitude).reduce((a, b) => a > b ? a : b);
  }

  double get minLng {
    return path.map((point) => point.longitude).reduce((a, b) => a < b ? a : b);
  }

  double get maxLng {
    return path.map((point) => point.longitude).reduce((a, b) => a > b ? a : b);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'city': city,
      'street_name': streetName,
      'path': path.map((point) => point.toJson()).toList(),
      'min_lat': minLat,
      'max_lat': maxLat,
      'min_lng': minLng,
      'max_lng': maxLng,
    };
  }

  String toCsvLine() {
    final row = [
      id,
      city,
      streetName,
      jsonEncode(path.map((point) => point.toJson()).toList()),
      minLat.toString(),
      maxLat.toString(),
      minLng.toString(),
      maxLng.toString(),
    ];

    return row.map(csvEscape).join(',');
  }
}

String csvEscape(String value) {
  if (!value.contains(',') && !value.contains('"') && !value.contains('\n')) {
    return value;
  }

  return '"${value.replaceAll('"', '""')}"';
}
