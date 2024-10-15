import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:math';
import 'dart:convert';

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
    String path = join(await getDatabasesPath(), 'autour.db');
    //print("[+] DEBUG, db path = $path");

    // Delete the existing database
    //await deleteDatabase(path);

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
}
