// lib/db/database_helper.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  // ── Singleton ──────────────────────────────────────────────
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  static DatabaseHelper get instance => _instance;
  DatabaseHelper._internal();

  static Database? _db;

  static const String _dbName    = 'smart_inventory.db';
  static const int    _dbVersion = 3;

  // ── Accès à la base ────────────────────────────────────────
  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, _dbName);

    return openDatabase(
      path,
      version: _dbVersion,
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ── Création des tables ─────────────────────────────────────
  Future<void> _onCreate(Database db, int version) async {
    await db.transaction((txn) async {
      await txn.execute('''
        CREATE TABLE users (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          email         TEXT    NOT NULL UNIQUE,
          password_hash TEXT    NOT NULL,
          pharmacy_name TEXT,
          created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
          last_login    TEXT
        )
      ''');

      await txn.execute('''
        CREATE TABLE medicines (
          id            INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id       INTEGER NOT NULL,
          name          TEXT    NOT NULL,
          dosage        TEXT,
          form          TEXT,
          category      TEXT,
          manufacturer  TEXT,
          barcode       TEXT,
          stock         INTEGER NOT NULL DEFAULT 0,
          min_stock     INTEGER NOT NULL DEFAULT 10,
          unit          TEXT    DEFAULT 'box',
          notes         TEXT,
          image_path    TEXT,
          created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
          updated_at    TEXT    NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
          UNIQUE(user_id, barcode)
        )
      ''');
      await txn.execute('CREATE INDEX idx_medicines_name     ON medicines(name)');
      await txn.execute('CREATE INDEX idx_medicines_category ON medicines(category)');
      await txn.execute('CREATE INDEX idx_medicines_user     ON medicines(user_id)');

      await txn.execute('''
        CREATE TABLE inventory_sessions (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id      INTEGER NOT NULL,
          session_code TEXT,
          label        TEXT    NOT NULL DEFAULT 'Session',
          status       TEXT    NOT NULL DEFAULT 'active',
          total_boxes  INTEGER NOT NULL DEFAULT 0,
          total_zones  INTEGER NOT NULL DEFAULT 0,
          started_at   TEXT    NOT NULL DEFAULT (datetime('now')),
          ended_at     TEXT,
          notes        TEXT,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('CREATE INDEX idx_sessions_user ON inventory_sessions(user_id)');

      await txn.execute('''
        CREATE TABLE scan_zones (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id   INTEGER NOT NULL,
          zone_name    TEXT    NOT NULL,
          status       TEXT    NOT NULL DEFAULT 'pending',
          boxes        INTEGER NOT NULL DEFAULT 0,
          total_boxes  INTEGER NOT NULL DEFAULT 0,
          scanned_at   TEXT,
          image_path   TEXT,
          notes        TEXT,
          FOREIGN KEY (session_id) REFERENCES inventory_sessions(id) ON DELETE CASCADE
        )
      ''');
      await txn.execute('CREATE INDEX idx_zones_session ON scan_zones(session_id)');

      await txn.execute('''
        CREATE TABLE zone_medicines (
          id        INTEGER PRIMARY KEY AUTOINCREMENT,
          zone_id   INTEGER NOT NULL,
          name      TEXT    NOT NULL,
          FOREIGN KEY (zone_id) REFERENCES scan_zones(id) ON DELETE CASCADE
        )
      ''');

      await txn.execute('''
        CREATE TABLE alerts (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          medicine_id INTEGER NOT NULL,
          is_read     INTEGER NOT NULL DEFAULT 0,
          created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE CASCADE
        )
      ''');

      await txn.execute('''
        CREATE TABLE scan_detections (
          id                INTEGER PRIMARY KEY AUTOINCREMENT,
          zone_id           INTEGER NOT NULL,
          medicine_id       INTEGER,
          raw_ocr_text      TEXT,
          matched_name      TEXT,
          dosage_detected   TEXT,
          form_detected     TEXT,
          confidence        REAL    DEFAULT 0.0,
          ocr_confidence    REAL    DEFAULT 0.0,
          quantity          INTEGER NOT NULL DEFAULT 1,
          crop_image_path   TEXT,
          is_confirmed      INTEGER NOT NULL DEFAULT 0,
          detected_at       TEXT    NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (zone_id)     REFERENCES scan_zones(id)  ON DELETE CASCADE,
          FOREIGN KEY (medicine_id) REFERENCES medicines(id)   ON DELETE SET NULL
        )
      ''');
      await txn.execute('CREATE INDEX idx_detections_zone     ON scan_detections(zone_id)');
      await txn.execute('CREATE INDEX idx_detections_medicine ON scan_detections(medicine_id)');

      await txn.execute('''
        CREATE TABLE stock_movements (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          medicine_id      INTEGER NOT NULL,
          session_id       INTEGER,
          movement_type    TEXT    NOT NULL,
          quantity_before  INTEGER NOT NULL DEFAULT 0,
          quantity_change  INTEGER NOT NULL,
          quantity_after   INTEGER NOT NULL DEFAULT 0,
          reason           TEXT,
          moved_at         TEXT    NOT NULL DEFAULT (datetime('now')),
          FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE CASCADE,
          FOREIGN KEY (session_id)  REFERENCES inventory_sessions(id) ON DELETE SET NULL
        )
      ''');
      await txn.execute('CREATE INDEX idx_movements_medicine ON stock_movements(medicine_id)');
      await txn.execute('CREATE INDEX idx_movements_session  ON stock_movements(session_id)');

      await txn.execute('''
        CREATE VIEW v_low_stock AS
        SELECT id, user_id, name, dosage, category, stock, min_stock,
               (min_stock - stock) AS shortage,
               CASE
                 WHEN stock = 0               THEN 'out_of_stock'
                 WHEN stock < min_stock * 0.3 THEN 'critical'
                 WHEN stock < min_stock * 0.6 THEN 'urgent'
                 ELSE 'warning'
               END AS severity
        FROM medicines
        WHERE stock < min_stock
      ''');
    });
  }

  // ── Migrations ────────────────────────────────────────────
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2 → v3 : crée les tables zone_medicines et alerts manquantes
    if (oldVersion < 3) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS zone_medicines (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            zone_id INTEGER NOT NULL,
            name    TEXT    NOT NULL,
            FOREIGN KEY (zone_id) REFERENCES scan_zones(id) ON DELETE CASCADE
          )
        ''');
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS alerts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_id INTEGER NOT NULL,
            is_read     INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT    NOT NULL DEFAULT (datetime(\'now\')),
            FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE CASCADE
          )
        ''');
        try { await txn.execute('ALTER TABLE inventory_sessions ADD COLUMN session_code TEXT'); } catch (_) {}
        try { await txn.execute('ALTER TABLE scan_zones ADD COLUMN boxes INTEGER NOT NULL DEFAULT 0'); } catch (_) {}
      });
    }

    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS users (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            email         TEXT    NOT NULL UNIQUE,
            password_hash TEXT    NOT NULL,
            pharmacy_name TEXT,
            created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
            last_login    TEXT
          )
        ''');
        await txn.execute('ALTER TABLE medicines ADD COLUMN user_id INTEGER');
        await txn.execute('ALTER TABLE inventory_sessions ADD COLUMN user_id INTEGER');
        await txn.execute('''
          INSERT INTO users (email, password_hash, pharmacy_name)
          VALUES ('legacy@local.inventory', 'dummy_hash_migration', 'Migrated Pharmacy')
        ''');
        final rows = await txn.rawQuery('SELECT last_insert_rowid() as id');
        final userId = rows.first['id'] as int;
        await txn.update('medicines', {'user_id': userId}, where: 'user_id IS NULL');
        await txn.update('inventory_sessions', {'user_id': userId}, where: 'user_id IS NULL');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_medicines_user ON medicines(user_id)');
        await txn.execute('CREATE INDEX IF NOT EXISTS idx_sessions_user ON inventory_sessions(user_id)');

        // Crée les nouvelles tables si elles n'existent pas encore
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS zone_medicines (
            id      INTEGER PRIMARY KEY AUTOINCREMENT,
            zone_id INTEGER NOT NULL,
            name    TEXT    NOT NULL,
            FOREIGN KEY (zone_id) REFERENCES scan_zones(id) ON DELETE CASCADE
          )
        ''');
        await txn.execute('''
          CREATE TABLE IF NOT EXISTS alerts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            medicine_id INTEGER NOT NULL,
            is_read     INTEGER NOT NULL DEFAULT 0,
            created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
            FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE CASCADE
          )
        ''');
      });
    }
  }

  // ════════════════════════════════════════════════════════════
  // MÉTHODES SESSIONS
  // ════════════════════════════════════════════════════════════

  /// Retourne la session active (status='active'), ou null
  Future<Map<String, dynamic>?> getActiveSession() async {
    final db = await database;
    final rows = await db.query(
      'inventory_sessions',
      where: 'status = ?',
      whereArgs: ['active'],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Crée une nouvelle session et retourne son id
  Future<int> createSession(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('inventory_sessions', data);
  }

  /// Met à jour une session existante
  Future<void> updateSession(int sessionId, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'inventory_sessions',
      data,
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // ════════════════════════════════════════════════════════════
  // MÉTHODES ZONES
  // ════════════════════════════════════════════════════════════

  /// Retourne toutes les zones d'une session
  Future<List<Map<String, dynamic>>> getZonesForSession(int sessionId) async {
    final db = await database;
    return db.query(
      'scan_zones',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
  }

  /// Insère une zone et retourne son id
  Future<int> insertZone(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('scan_zones', data);
  }

  /// Met à jour une zone
  Future<void> updateZone(int zoneId, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'scan_zones',
      data,
      where: 'id = ?',
      whereArgs: [zoneId],
    );
  }

  // ════════════════════════════════════════════════════════════
  // MÉTHODES ZONE_MEDICINES (médicaments simples par zone)
  // ════════════════════════════════════════════════════════════

  /// Retourne les noms de médicaments d'une zone
  Future<List<String>> getMedicinesForZone(int zoneId) async {
    final db = await database;
    final rows = await db.query(
      'zone_medicines',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
    );
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Supprime tous les médicaments d'une zone (avant réinsertion)
  Future<void> deleteZoneMedicines(int zoneId) async {
    final db = await database;
    await db.delete(
      'zone_medicines',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
    );
  }

  /// Insère un médicament dans une zone
  Future<void> insertZoneMedicine(int zoneId, String medicineName) async {
    final db = await database;
    await db.insert('zone_medicines', {'zone_id': zoneId, 'name': medicineName});
  }

  // ════════════════════════════════════════════════════════════
  // MÉTHODES ALERTES
  // ════════════════════════════════════════════════════════════

  /// Retourne toutes les alertes (médicaments sous stock minimum)
  /// en joignant la vue v_low_stock avec la table alerts
  Future<List<Map<String, dynamic>>> getAlerts() async {
    final db = await database;
    // On lit directement depuis la vue v_low_stock
    // et on joint les alertes existantes pour le flag is_read
    final rows = await db.rawQuery('''
      SELECT
        m.id            AS id,
        m.id            AS medicine_id,
        m.name          AS medicine_name,
        m.stock         AS quantity,
        m.min_stock     AS min_stock,
        m.category      AS category,
        CASE
          WHEN m.stock = 0               THEN 'out_of_stock'
          WHEN m.stock < m.min_stock * 0.3 THEN 'critical'
          WHEN m.stock < m.min_stock * 0.6 THEN 'urgent'
          ELSE 'warning'
        END AS severity,
        COALESCE(a.is_read, 0) AS is_read
      FROM medicines m
      LEFT JOIN alerts a ON a.medicine_id = m.id
      WHERE m.stock < m.min_stock
      ORDER BY m.stock ASC
    ''');
    return rows;
  }

  /// Recrée les alertes depuis l'état actuel du stock
  Future<void> refreshAlerts() async {
    final db = await database;
    // Supprime les alertes pour les médicaments qui ne sont plus en rupture
    await db.rawDelete('''
      DELETE FROM alerts
      WHERE medicine_id IN (
        SELECT id FROM medicines WHERE stock >= min_stock
      )
    ''');
    // Insère les alertes manquantes pour les médicaments en rupture
    await db.rawInsert('''
      INSERT OR IGNORE INTO alerts (medicine_id)
      SELECT id FROM medicines
      WHERE stock < min_stock
        AND id NOT IN (SELECT medicine_id FROM alerts)
    ''');
  }

  /// Marque toutes les alertes comme lues
  Future<void> markAllAlertsRead() async {
    final db = await database;
    await db.update('alerts', {'is_read': 1});
  }

  // ════════════════════════════════════════════════════════════
  // MÉTHODES USERS
  // ════════════════════════════════════════════════════════════

  Future<void> close() async {
    final db = await database;
    await db.close();
    _db = null;
  }

  Future<void> resetAll() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.execute('DELETE FROM stock_movements');
      await txn.execute('DELETE FROM scan_detections');
      await txn.execute('DELETE FROM zone_medicines');
      await txn.execute('DELETE FROM scan_zones');
      await txn.execute('DELETE FROM inventory_sessions');
      await txn.execute('DELETE FROM alerts');
      await txn.execute('DELETE FROM medicines');
      await txn.execute('DELETE FROM users');
      await txn.execute(
        "DELETE FROM sqlite_sequence WHERE name IN "
        "('users','medicines','inventory_sessions','scan_zones','scan_detections','stock_movements','alerts','zone_medicines')",
      );
    });
  }
}