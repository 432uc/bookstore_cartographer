import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'models/bookstore.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bookstore_cartographer.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE stores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        station TEXT,
        registers INTEGER,
        has_toilet INTEGER DEFAULT 0,
        has_cafe INTEGER DEFAULT 0,
        address TEXT,
        path_data TEXT,
        area REAL
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE stores ADD COLUMN has_toilet INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE stores ADD COLUMN has_cafe INTEGER DEFAULT 0');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE stores ADD COLUMN station TEXT');
      await db.execute('ALTER TABLE stores ADD COLUMN registers INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE stores ADD COLUMN address TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE stores ADD COLUMN path_data TEXT');
      await db.execute('ALTER TABLE stores ADD COLUMN area REAL');
    }
  }

  Future<int> insertStore(Bookstore store) async {
    final db = await instance.database;
    return await db.insert('stores', store.toMap());
  }

  Future<List<Bookstore>> queryAllStores() async {
    final db = await instance.database;
    final result = await db.query('stores', orderBy: 'id DESC');
    return result.map((json) => Bookstore(
      id: json['id'] as int?,
      name: json['name'] as String,
      station: (json['station'] as String?) ?? '',
      registers: (json['registers'] as int?) ?? 0,
      hasToilet: (json['has_toilet'] as int) == 1,
      hasCafe: (json['has_cafe'] as int) == 1,
      address: (json['address'] as String?) ?? '',
      pathData: json['path_data'] as String?,
      area: json['area'] as double?,
    )).toList();
  }

  Future<int> updateStore(Bookstore store) async {
    final db = await instance.database;
    return await db.update(
      'stores',
      store.toMap(),
      where: 'id = ?',
      whereArgs: [store.id],
    );
  }
}
