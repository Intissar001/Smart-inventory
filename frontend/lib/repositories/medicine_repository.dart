import 'package:sqflite/sqflite.dart';
import '../db/database_helper.dart';
import '../models/medicine.dart';
import '../models/stock_movement.dart';
import '../services/auth_service.dart';

class MedicineRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AuthService _auth = AuthService();

  int _getCurrentUserId() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');
    return user.id!;
  }

  // ── Lecture ────────────────────────────────────────────────
  Future<List<Medicine>> getAll() async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'medicines',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'name ASC',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  Future<Medicine?> getById(int id) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'medicines',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
    return rows.isEmpty ? null : Medicine.fromMap(rows.first);
  }

  Future<List<Medicine>> search(String query) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'medicines',
      where: 'user_id = ? AND LOWER(name) LIKE ?',
      whereArgs: [userId, '%${query.toLowerCase()}%'],
      orderBy: 'name ASC',
    );
    return rows.map(Medicine.fromMap).toList();
  }

  Future<List<Map<String, dynamic>>> getLowStock() async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    return db.rawQuery('''
      SELECT id, name, dosage, category, stock, min_stock,
             (min_stock - stock) AS shortage,
             CASE
               WHEN stock = 0 THEN 'out_of_stock'
               WHEN stock < min_stock * 0.3 THEN 'critical'
               WHEN stock < min_stock * 0.6 THEN 'urgent'
               ELSE 'warning'
             END AS severity
      FROM medicines
      WHERE user_id = ? AND stock < min_stock
      ORDER BY stock ASC
    ''', [userId]);
  }

  Future<Medicine?> findByExactName(String name) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'medicines',
      where: 'user_id = ? AND LOWER(name) = ?',
      whereArgs: [userId, name.toLowerCase().trim()],
      limit: 1,
    );
    return rows.isEmpty ? null : Medicine.fromMap(rows.first);
  }

  // ── Écriture ───────────────────────────────────────────────
  Future<Medicine> insert(Medicine medicine) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final map = medicine.toMap();
    map['user_id'] = userId;
    final id = await db.insert('medicines', map);
    return medicine.copyWith(id: id);
  }

  Future<void> update(Medicine medicine) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    await db.update(
      'medicines',
      medicine.toMap(),
      where: 'id = ? AND user_id = ?',
      whereArgs: [medicine.id, userId],
    );
  }

  Future<void> delete(int id) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    await db.delete(
      'medicines',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  // ── Gestion du stock ───────────────────────────────────────
  Future<void> addStock({
    required int medicineId,
    required int quantity,
    int? sessionId,
    String movementType = 'scan_add',
    String? reason,
  }) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();

    await db.transaction((txn) async {
      final rows = await txn.query(
        'medicines',
        columns: ['stock'],
        where: 'id = ? AND user_id = ?',
        whereArgs: [medicineId, userId],
      );
      if (rows.isEmpty) throw Exception('Médicament non trouvé');
      final before = rows.first['stock'] as int;
      final after = before + quantity;

      await txn.update(
        'medicines',
        {'stock': after, 'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ? AND user_id = ?',
        whereArgs: [medicineId, userId],
      );

      await txn.insert('stock_movements', {
        'medicine_id': medicineId,
        'session_id': sessionId,
        'movement_type': movementType,
        'quantity_before': before,
        'quantity_change': quantity,
        'quantity_after': after,
        'reason': reason,
      });
    });
  }

  Future<void> removeStock({
    required int medicineId,
    required int quantity,
    int? sessionId,
    String? reason,
  }) async {
    await addStock(
      medicineId: medicineId,
      quantity: -quantity,
      sessionId: sessionId,
      movementType: 'manual_remove',
      reason: reason,
    );
  }

  // ── OCR : trouver ou créer ─────────────────────────────────
  Future<Medicine> findOrCreateFromOcr({
    required String name,
    String? dosage,
    String? form,
    String? category,
    String? manufacturer,
    String? imagePath,
    int quantity = 1,
    int? sessionId,
  }) async {
    Medicine? existing = await findByExactName(name);
    if (existing != null) {
      await addStock(
        medicineId: existing.id!,
        quantity: quantity,
        sessionId: sessionId,
        movementType: 'scan_add',
        reason: 'Scan automatique OCR',
      );
      return (await getById(existing.id!))!;
    } else {
      final newMedicine = Medicine(
        userId: _getCurrentUserId(),
        name: name,
        dosage: dosage,
        form: form,
        category: category,
        manufacturer: manufacturer,
        stock: quantity,
        minStock: 10,
        imagePath: imagePath,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final created = await insert(newMedicine);
      final db = await _dbHelper.database;
      await db.insert('stock_movements', {
        'medicine_id': created.id,
        'session_id': sessionId,
        'movement_type': 'scan_add',
        'quantity_before': 0,
        'quantity_change': quantity,
        'quantity_after': quantity,
        'reason': 'Premier scan — création automatique',
      });
      return created;
    }
  }
}