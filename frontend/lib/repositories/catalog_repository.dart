// lib/repositories/catalog_repository.dart
//
// Manages:
//   • catalog_medicines  – global table seeded from medicines2.json (shared)
//   • user_medicine_stock – per-user stock / min-stock overrides
//
// On first launch the catalog table is populated from the JSON asset.
// Subsequent launches detect the table is already populated and skip seeding.

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/catalog_medicine.dart';

class CatalogRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── Public API ─────────────────────────────────────────────

  /// Seed catalog from JSON if not yet done, then return all medicines
  /// with the per-user stock/min for [userId].
  Future<List<CatalogMedicine>> getAllForUser(int userId) async {
    final db = await _dbHelper.database;
    await _seedIfNeeded(db);
    return _fetchAll(db, userId);
  }

  /// Search by name or category for a given user.
  Future<List<CatalogMedicine>> searchForUser(
      int userId, String query) async {
    final db = await _dbHelper.database;
    await _seedIfNeeded(db);
    final q = '%${query.toLowerCase()}%';
    final rows = await db.rawQuery('''
      SELECT
        cm.id,
        cm.name,
        cm.manufacturer,
        cm.category,
        COALESCE(ums.stock,     0) AS stock,
        COALESCE(ums.min_stock, 0) AS min_stock
      FROM catalog_medicines cm
      LEFT JOIN user_medicine_stock ums
             ON ums.catalog_medicine_id = cm.id AND ums.user_id = ?
      WHERE LOWER(cm.name) LIKE ? OR LOWER(cm.category) LIKE ?
      ORDER BY cm.name ASC
    ''', [userId, q, q]);
    return rows
        .map((r) => CatalogMedicine.fromRow(r, userId))
        .toList();
  }

  /// Update (or insert) per-user stock & min_stock.
  Future<void> upsertStock({
    required int userId,
    required int catalogMedicineId,
    required int stock,
    required int minStock,
  }) async {
    final db = await _dbHelper.database;
    await db.execute('''
      INSERT INTO user_medicine_stock (user_id, catalog_medicine_id, stock, min_stock)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(user_id, catalog_medicine_id)
      DO UPDATE SET stock = excluded.stock, min_stock = excluded.min_stock
    ''', [userId, catalogMedicineId, stock, minStock]);
  }

  /// Add [quantity] to the current stock of a medicine for [userId].
  /// Used after a scan session detects the medicine.
  Future<void> addToStock({
    required int userId,
    required int catalogMedicineId,
    required int quantity,
  }) async {
    final db = await _dbHelper.database;
    // Ensure a row exists first
    await db.execute('''
      INSERT OR IGNORE INTO user_medicine_stock
        (user_id, catalog_medicine_id, stock, min_stock)
      VALUES (?, ?, 0, 0)
    ''', [userId, catalogMedicineId]);

    await db.rawUpdate('''
      UPDATE user_medicine_stock
         SET stock = stock + ?
       WHERE user_id = ? AND catalog_medicine_id = ?
    ''', [quantity, userId, catalogMedicineId]);
  }

  /// Add a medicine manually (inserts into catalog_medicines if name not found,
  /// then upserts user stock).
  Future<CatalogMedicine> addManualMedicine({
    required int    userId,
    required String name,
    required String manufacturer,
    required String category,
    required int    stock,
    required int    minStock,
  }) async {
    final db = await _dbHelper.database;

    // Try to find existing catalog entry by exact name (case-insensitive)
    final existing = await db.rawQuery(
      'SELECT id FROM catalog_medicines WHERE LOWER(name) = ? LIMIT 1',
      [name.trim().toLowerCase()],
    );

    int catalogId;
    if (existing.isNotEmpty) {
      catalogId = existing.first['id'] as int;
    } else {
      catalogId = await db.insert('catalog_medicines', {
        'name':         name.trim(),
        'manufacturer': manufacturer.trim(),
        'category':     category.trim(),
      });
    }

    await upsertStock(
      userId:             userId,
      catalogMedicineId:  catalogId,
      stock:              stock,
      minStock:           minStock,
    );

    final rows = await db.rawQuery('''
      SELECT
        cm.id, cm.name, cm.manufacturer, cm.category,
        COALESCE(ums.stock, 0)     AS stock,
        COALESCE(ums.min_stock, 0) AS min_stock
      FROM catalog_medicines cm
      LEFT JOIN user_medicine_stock ums
             ON ums.catalog_medicine_id = cm.id AND ums.user_id = ?
      WHERE cm.id = ?
    ''', [userId, catalogId]);

    return CatalogMedicine.fromRow(rows.first, userId);
  }

  /// Delete a user's custom medicine (only removes catalog entry if it was
  /// manually added AND has no other users' stock rows).
  Future<void> deleteUserMedicine({
    required int userId,
    required int catalogMedicineId,
  }) async {
    final db = await _dbHelper.database;
    await db.delete(
      'user_medicine_stock',
      where: 'user_id = ? AND catalog_medicine_id = ?',
      whereArgs: [userId, catalogMedicineId],
    );
  }

  // ── Internal ───────────────────────────────────────────────

  Future<List<CatalogMedicine>> _fetchAll(Database db, int userId) async {
    final rows = await db.rawQuery('''
      SELECT
        cm.id,
        cm.name,
        cm.manufacturer,
        cm.category,
        COALESCE(ums.stock,     0) AS stock,
        COALESCE(ums.min_stock, 0) AS min_stock
      FROM catalog_medicines cm
      LEFT JOIN user_medicine_stock ums
             ON ums.catalog_medicine_id = cm.id AND ums.user_id = ?
      ORDER BY cm.name ASC
    ''', [userId]);
    return rows.map((r) => CatalogMedicine.fromRow(r, userId)).toList();
  }

  // ── Seeding ────────────────────────────────────────────────

  static bool _seeded = false;

  Future<void> _seedIfNeeded(Database db) async {
    if (_seeded) return;

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM catalog_medicines'),
    ) ?? 0;

    if (count > 0) {
      _seeded = true;
      return;
    }

    // Load from asset
    final jsonStr =
        await rootBundle.loadString('assets/data/medicines2.json');
    final List<dynamic> list = jsonDecode(jsonStr);

    final batch = db.batch();
    for (final item in list) {
      batch.insert(
        'catalog_medicines',
        {
          'name':         (item['name']         as String? ?? '').trim(),
          'manufacturer': (item['manufacturer']  as String? ?? '').trim(),
          'category':     (item['category']      as String? ?? '').trim(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    _seeded = true;
  }
}
