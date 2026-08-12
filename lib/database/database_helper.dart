import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/deteksi_model.dart';

/// Helper Singleton untuk mengelola database SQLite lokal (on-device,
/// tanpa server) sesuai keputusan Deployment Diagram Bab IV.
class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'egg_crack_detector.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE hasil_deteksi (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tanggal TEXT NOT NULL,
            gambar_path TEXT NOT NULL,
            hasil_klasifikasi TEXT NOT NULL,
            confidence_score REAL NOT NULL
          )
        ''');
      },
    );
  }

  /// Menyimpan satu hasil deteksi baru ke riwayat.
  Future<int> insertDeteksi(DeteksiResult result) async {
    final db = await database;
    return await db.insert(
      'hasil_deteksi',
      result.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Mengambil seluruh riwayat, terbaru di atas.
  Future<List<DeteksiResult>> getAllDeteksi() async {
    final db = await database;
    final maps = await db.query('hasil_deteksi', orderBy: 'tanggal DESC');
    return maps.map((m) => DeteksiResult.fromMap(m)).toList();
  }

  /// Hapus satu entri riwayat berdasarkan id (opsional, untuk fitur swipe-delete).
  Future<int> deleteDeteksi(int id) async {
    final db = await database;
    return await db.delete('hasil_deteksi', where: 'id = ?', whereArgs: [id]);
  }
}
