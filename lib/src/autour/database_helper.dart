import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

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

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future _onCreate(Database db, int version) async {
    await db.execute('''
    CREATE TABLE places (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      formatted_address TEXT,
      google_maps_uri TEXT,
      primary_type TEXT,
      display_name TEXT,
      location TEXT,
      current_opening_hours TEXT
    )
    ''');
  }

  Future<int> insertPlace(Map<String, dynamic> place) async {
    Database db = await database;
    return await db.insert('places', place);
  }

  Future<List<Map<String, dynamic>>> queryAllPlaces() async {
    Database db = await database;
    return await db.query('places');
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
}
