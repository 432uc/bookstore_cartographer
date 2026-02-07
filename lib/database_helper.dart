import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    print('Database: initialize start');
    _database = await _initDB('bookstore_web.db');
    print('Database: initialize end');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    print('Database: initialize for path $filePath (Web: $kIsWeb)');
    
    // Webの場合はパス結合をスキップ
    String path;
    if (kIsWeb) {
      path = filePath;
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, filePath);
    }
    
    print('Database: opening database at $path');
    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // テーブルの作成（最初は「本屋」テーブル）
  Future _createDB(Database db, int version) async {
    print('Database: creating table stores');
    await db.execute('''
      CREATE TABLE stores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        branch TEXT,
        memo TEXT,
        visit_date TEXT,
        has_toilet INTEGER DEFAULT 0,
        has_cafe INTEGER DEFAULT 0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    print('Database: upgrading from $oldVersion to $newVersion');
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE stores ADD COLUMN has_toilet INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE stores ADD COLUMN has_cafe INTEGER DEFAULT 0');
    }
  }

  // データの登録用メソッド
  Future<int> insertStore(Map<String, dynamic> row) async {
    print('Database: insertStoreInternal start');
    final db = await instance.database;
    final id = await db.insert('stores', row);
    print('Database: insertStoreInternal end, id: $id');
    return id;
  }
  // database_helper.dart の中に追加
  Future<List<Map<String, dynamic>>> queryAllStores() async {
    print('Database: queryAllStores start');
    final db = await instance.database;
    // storesテーブルのデータをすべて取得（新しい順：id DESC）
    final result = await db.query('stores', orderBy: 'id DESC');
    print('Database: queryAllStores end, count: ${result.length}');
    return result;
  }
}