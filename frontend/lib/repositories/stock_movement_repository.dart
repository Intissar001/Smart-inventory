// lib/repositories/stock_movement_repository.dart
//
// Lecture de l'historique des mouvements de stock.
// Les écritures passent par MedicineRepository (addStock / removeStock / adjustStock)
// pour garantir la cohérence entre le stock et l'historique.

import '../db/database_helper.dart';
import '../models/stock_movement.dart';

class StockMovementRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── Lecture ────────────────────────────────────────────────

  /// Tous les mouvements d'un médicament (du plus récent au plus ancien)
  Future<List<StockMovement>> getForMedicine(int medicineId) async {
    final db   = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      where:     'medicine_id = ?',
      whereArgs: [medicineId],
      orderBy:   'moved_at DESC',
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  /// Tous les mouvements liés à une session
  Future<List<StockMovement>> getForSession(int sessionId) async {
    final db   = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      where:     'session_id = ?',
      whereArgs: [sessionId],
      orderBy:   'moved_at DESC',
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  /// Tous les mouvements récents (toutes sessions confondues, limité à [limit])
  Future<List<StockMovement>> getRecent({int limit = 50}) async {
    final db   = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      orderBy: 'moved_at DESC',
      limit:   limit,
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  /// Mouvements filtrés par type
  Future<List<StockMovement>> getByType(String movementType) async {
    final db   = await _dbHelper.database;
    final rows = await db.query(
      'stock_movements',
      where:     'movement_type = ?',
      whereArgs: [movementType],
      orderBy:   'moved_at DESC',
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  // ── Statistiques ───────────────────────────────────────────

  /// Total des entrées et sorties pour un médicament
  Future<Map<String, int>> getTotalsForMedicine(int medicineId) async {
    final db = await _dbHelper.database;

    final result = await db.rawQuery('''
      SELECT
        COALESCE(SUM(CASE WHEN quantity_change > 0 THEN  quantity_change ELSE 0 END), 0) AS total_in,
        COALESCE(SUM(CASE WHEN quantity_change < 0 THEN -quantity_change ELSE 0 END), 0) AS total_out
      FROM stock_movements
      WHERE medicine_id = ?
    ''', [medicineId]);

    return {
      'total_in':  (result.first['total_in']  as int?) ?? 0,
      'total_out': (result.first['total_out'] as int?) ?? 0,
    };
  }
}
