import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:math';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'globals.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;

  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'rund.sqlite');
    //print("[+] DEBUG, db path = $path");

    // Delete the existing database
    await deleteDatabase(path); // TEST

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE IF NOT EXISTS places (
        place_id INTEGER PRIMARY KEY AUTOINCREMENT,
        place_formatted_address TEXT UNIQUE,
        place_google_maps_uri TEXT,
        place_primary_type TEXT,
        place_display_name TEXT,
        place_longitude REAL,
        place_latitude REAL,
        place_current_opening_hours TEXT,
        place_country INTEGER,
        place_area_id INTEGER,
        last_updated DATE
    );
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS metadata (
        meta_user_id TEXT UNIQUE
    );
    ''');

    String userId = _generateRandomAsciiString(16);

    await db.insert(
      'metadata',
      {'meta_user_id': userId}
    );

    // Ping the backend to receive the trial credits
    _getTrialCredits();
  }

  String _generateRandomAsciiString(int length) {
    const String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final Random random = Random();

    return String.fromCharCodes(
      List.generate(length, (index) => chars.codeUnitAt(random.nextInt(chars.length)))
    );
  }

  Future<int> insertPlace(Map<String, dynamic> place) async {
    Database db = await database;
    String query = """
      INSERT INTO places (
        place_formatted_address, place_google_maps_uri, place_primary_type,
        place_display_name, place_longitude, place_latitude,
        place_current_opening_hours, place_country, place_area_id, last_updated
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(place_formatted_address)
      DO UPDATE SET
        place_google_maps_uri = excluded.place_google_maps_uri,
        place_primary_type = excluded.place_primary_type,
        place_display_name = excluded.place_display_name,
        place_longitude = excluded.place_longitude,
        place_latitude = excluded.place_latitude,
        place_current_opening_hours = excluded.place_current_opening_hours,
        place_country = excluded.place_country,
        place_area_id = excluded.place_area_id,
        last_updated = excluded.last_updated;
    """;

    List<dynamic> args = [
      place['place_formatted_address'],
      place['place_google_maps_uri'],
      place['place_primary_type'],
      place['place_display_name'],
      place['place_longitude'],
      place['place_latitude'],
      place['place_current_opening_hours'],
      place['place_country'],
      place['place_area_id'],
      place['last_updated'],
    ];

    return await db.rawInsert(query, args);
  }

  Future<List<Map<String, dynamic>>> queryAllPlaces() async {
    Database db = await database;
    return await db.query('places');
  }

  Future<List<Map<String, dynamic>>> queryPlaces(double lat, double lon, List<String> types) async {
    Database db = await database;

    Map<String, double> offsets = computeOffsetsFor1km(lat);
    double latStart = lat - (offsets['latitudeOffset'] ?? 0.0);
    double latEnd = lat + (offsets['latitudeOffset'] ?? 0.0);
    double lonStart = lon - (offsets['longitudeOffset'] ?? 0.0);
    double lonEnd = lon + (offsets['longitudeOffset'] ?? 0.0);

    // Round to 3 decimals for sql comparison
    latStart = double.parse(latStart.toStringAsFixed(3));
    latEnd = double.parse(latEnd.toStringAsFixed(3));
    lonStart = double.parse(lonStart.toStringAsFixed(3));
    lonEnd = double.parse(lonEnd.toStringAsFixed(3));

    // Prepare WHERE clause conditions
    String conditionsTypes = "";
    if (types.isNotEmpty) {
      conditionsTypes += "place_primary_type IN ('${types.join("', '")}')";
    }

    String query = """
      SELECT json_group_array(
        json_object(
          'place_id', place_id,
          'place_formatted_address', place_formatted_address,
          'place_google_maps_uri', place_google_maps_uri,
          'place_primary_type', place_primary_type,
          'place_display_name', place_display_name,
          'place_longitude', place_longitude,
          'place_latitude', place_latitude,
          'place_current_opening_hours', place_current_opening_hours,
          'place_country', place_country,
          'place_area_id', place_area_id,
          'last_updated', last_updated
        )
      ) as places
      FROM places
      WHERE $conditionsTypes
      AND place_latitude BETWEEN $latStart AND $latEnd
      AND place_longitude BETWEEN $lonStart AND $lonEnd;
    """;

    // Execute query
    List<Map<String, dynamic>> result = await db.rawQuery(query);

    // Return the list of places
    if (result.isNotEmpty && result[0] != null) {
      List<dynamic> places = json.decode(result[0]['places']);
      return places.cast<Map<String, dynamic>>();
    }

    return [];
  }

  Future<int> updatePlace(Map<String, dynamic> place) async {
    Database db = await database;
    int id = place['id'];
    return await db.update('places', place, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deletePlace(int id) async {
    Database db = await database;
    return await db.delete('places', where: 'id = ?', whereArgs: [id]);
  }

  // Function to compute 1 km offset in latitude and longitude
  Map<String, double> computeOffsetsFor1km(double latitude) {
    // Approximate km per degree of latitude (fixed)
    const double kmPerDegreeLatitude = 111.32;

    // Compute km per degree of longitude based on current latitude
    double kmPerDegreeLongitude = kmPerDegreeLatitude * cos(latitude * pi / 180);

    // Calculate the degree change for 1 km
    double deltaLatitude = 1 / kmPerDegreeLatitude;
    double deltaLongitude = 1 / kmPerDegreeLongitude;

    return {
      'latitudeOffset': deltaLatitude,
      'longitudeOffset': deltaLongitude,
    };
  }

  Future<String> getUserId() async {
    Database db = await database;
    String userId = "";

    final List<Map<String, dynamic>> result = await db.query(
      'metadata',
      columns: ['meta_user_id'],
      limit: 1,
    );

    if (result.isNotEmpty) {
      userId = result.first['meta_user_id'] as String;
    }

    return userId;
  }

  /// Send the newly created USER_ID to the backend to receive free credits for
  /// trial.
  Future<void> _getTrialCredits() async {
    final String url = BACKEND_URL + '/get-trial-credits';
    int credits = 0;

    // Get credits from backend
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode({
          'userId': USER_ID,
        }),
      );

      // Check if the response is successful (status code 200)
      if (response.statusCode != 200) {
        print('[-] Failed to load credits. Status code: ${response.statusCode}');
      }
    } catch (error) {
      print('[-] Error occurred while fetching credits: $error');
    }
  }
}
