import '../db/database_helper.dart';
import '../models/inventory_session.dart';
import '../models/scan_zone.dart';
import '../models/scan_detection.dart';
import '../services/auth_service.dart';

class SessionRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final AuthService _auth = AuthService();

  int _getCurrentUserId() {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Utilisateur non connecté');
    return user.id!;
  }

  // ========== SESSIONS ==========

  Future<List<InventorySession>> getAllSessions() async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'inventory_sessions',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'started_at DESC',
    );
    return rows.map(InventorySession.fromMap).toList();
  }

  Future<InventorySession?> getSessionById(int id) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'inventory_sessions',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
    return rows.isEmpty ? null : InventorySession.fromMap(rows.first);
  }

  Future<InventorySession?> getActiveSession() async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final rows = await db.query(
      'inventory_sessions',
      where: "status = 'active' AND user_id = ?",
      whereArgs: [userId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : InventorySession.fromMap(rows.first);
  }

  Future<InventorySession> startSession({String? label}) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final now = DateTime.now();

    final session = InventorySession(
      userId: userId,
      label: label ?? 'Session ${_formatDate(now)}',
      status: 'active',
      startedAt: now,
    );
    final id = await db.insert('inventory_sessions', session.toMap());
    return session.copyWith(id: id);
  }

  /// Met à jour le label (nom) d'une session
  Future<void> updateSessionLabel(int sessionId, String newLabel) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    await db.update(
      'inventory_sessions',
      {'label': newLabel},
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
  }

  Future<void> completeSession(int sessionId) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    final totalsResult = await db.rawQuery('''
      SELECT COUNT(*) AS zone_count, COALESCE(SUM(total_boxes), 0) AS box_sum
      FROM scan_zones
      WHERE session_id = ? AND status = 'done'
    ''', [sessionId]);
    final zoneCount = (totalsResult.first['zone_count'] as int?) ?? 0;
    final boxSum    = (totalsResult.first['box_sum']    as int?) ?? 0;

    await db.update(
      'inventory_sessions',
      {
        'status':      'completed',
        'ended_at':    DateTime.now().toIso8601String(),
        'total_zones': zoneCount,
        'total_boxes': boxSum,
      },
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
  }

  Future<void> cancelSession(int sessionId) async {
    final db = await _dbHelper.database;
    final userId = _getCurrentUserId();
    await db.update(
      'inventory_sessions',
      {'status': 'cancelled', 'ended_at': DateTime.now().toIso8601String()},
      where: 'id = ? AND user_id = ?',
      whereArgs: [sessionId, userId],
    );
  }

  // ========== ZONES ==========

  Future<ScanZone> addZone({
    required int sessionId,
    required String zoneName,
    String? imagePath,
  }) async {
    final db = await _dbHelper.database;
    final zone = ScanZone(
      sessionId: sessionId,
      zoneName: zoneName,
      status: 'pending',
      imagePath: imagePath,
    );
    final id = await db.insert('scan_zones', zone.toMap());
    return zone.copyWith(id: id);
  }

  Future<List<ScanZone>> getZonesForSession(int sessionId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'scan_zones',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
    return rows.map(ScanZone.fromMap).toList();
  }

  Future<void> completeZone({
    required int zoneId,
    required int totalBoxes,
    String? imagePath,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'scan_zones',
      {
        'status':      'done',
        'total_boxes': totalBoxes,
        'scanned_at':  DateTime.now().toIso8601String(),
        if (imagePath != null) 'image_path': imagePath,
      },
      where: 'id = ?',
      whereArgs: [zoneId],
    );
  }

  // ========== DÉTECTIONS ==========

  Future<List<ScanDetection>> getDetectionsForZone(int zoneId) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'scan_detections',
      where: 'zone_id = ?',
      whereArgs: [zoneId],
      orderBy: 'detected_at ASC',
    );
    return rows.map(ScanDetection.fromMap).toList();
  }

  Future<void> addDetection(ScanDetection detection) async {
    final db = await _dbHelper.database;
    await db.insert('scan_detections', detection.toMap());
  }

  Future<void> addDetectionsBatch(List<ScanDetection> detections) async {
    final db = await _dbHelper.database;
    final batch = db.batch();
    for (final det in detections) {
      batch.insert('scan_detections', det.toMap());
    }
    await batch.commit(noResult: true);
  }

  // ========== ZONES (suite) ==========

  /// Met à jour le nom d'une zone
  Future<void> updateZoneName(int zoneId, String newName) async {
    final db = await _dbHelper.database;
    await db.update(
      'scan_zones',
      {'zone_name': newName},
      where: 'id = ?',
      whereArgs: [zoneId],
    );
  }

  /// Supprime une zone et toutes ses détections
  Future<void> deleteZone(int zoneId) async {
    final db = await _dbHelper.database;
    await db.delete('scan_detections', where: 'zone_id = ?', whereArgs: [zoneId]);
    await db.delete('scan_zones', where: 'id = ?', whereArgs: [zoneId]);
  }

  // ========== DÉTECTIONS ==========

  /// Met à jour le nom et la quantité d'une détection
  Future<void> updateDetection(int detectionId, {String? matchedName, int? quantity}) async {
    final db = await _dbHelper.database;
    final data = <String, dynamic>{};
    if (matchedName != null) data['matched_name'] = matchedName;
    if (quantity != null) data['quantity'] = quantity;
    if (data.isEmpty) return;
    await db.update('scan_detections', data, where: 'id = ?', whereArgs: [detectionId]);
  }

  /// Supprime une détection individuelle et met à jour le total_boxes de la zone
  Future<void> deleteDetection(int detectionId, int zoneId) async {
    final db = await _dbHelper.database;
    await db.delete('scan_detections', where: 'id = ?', whereArgs: [detectionId]);
    // Recalcule total_boxes
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS total FROM scan_detections WHERE zone_id = ?',
      [zoneId],
    );
    final total = (result.first['total'] as int?) ?? 0;
    await db.update('scan_zones', {'total_boxes': total}, where: 'id = ?', whereArgs: [zoneId]);
  }

  /// Ajoute une détection manuelle dans une zone
  Future<void> insertDetection(ScanDetection detection) async {
    final db = await _dbHelper.database;
    await db.insert('scan_detections', detection.toMap());
    // Recalcule total_boxes
    final result = await db.rawQuery(
      'SELECT COALESCE(SUM(quantity), 0) AS total FROM scan_detections WHERE zone_id = ?',
      [detection.zoneId],
    );
    final total = (result.first['total'] as int?) ?? 0;
    await db.update('scan_zones', {'total_boxes': total},
        where: 'id = ?', whereArgs: [detection.zoneId]);
  }

  // ========== UTILITAIRE ==========

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  /// Supprime définitivement une session, ses zones et ses détections
    Future<void> deleteSession(int sessionId) async {
      final db = await _dbHelper.database;
      final userId = _getCurrentUserId();

      // 1. Récupérer toutes les zones de cette session pour supprimer leurs détections
      final zones = await db.query('scan_zones', where: 'session_id = ?', whereArgs: [sessionId]);
      for (var zone in zones) {
        await db.delete('scan_detections', where: 'zone_id = ?', whereArgs: [zone['id']]);
      }

      // 2. Supprimer les zones
      await db.delete('scan_zones', where: 'session_id = ?', whereArgs: [sessionId]);

      // 3. Supprimer la session
      await db.delete(
        'inventory_sessions',
        where: 'id = ? AND user_id = ?',
        whereArgs: [sessionId, userId],
      );
    }
}