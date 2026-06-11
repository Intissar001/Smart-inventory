// lib/providers/session_provider.dart
//
// Provider global qui :
//  • tient l'ID de la session active
//  • reçoit les résultats de scan depuis N'IMPORTE QUELLE page
//    (FAB, HeroCard, bouton SessionScreen…)
//  • persiste les zones + médicaments (avec dosage/form/count) en base
//  • notifie SessionScreen (ou tout autre listener) pour se rafraîchir
//
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';

// ── Modèle riche par médicament dans une zone ────────────────────────────────
class ZoneMedEntry {
  final String name;
  final String dosage;
  final String form;
  final int count;

  const ZoneMedEntry({
    required this.name,
    required this.dosage,
    required this.form,
    required this.count,
  });

  factory ZoneMedEntry.fromMap(Map<String, dynamic> m) => ZoneMedEntry(
        name:   (m['name']   as String?) ?? '',
        dosage: (m['dosage'] as String?) ?? '',
        form:   (m['form']   as String?) ?? '',
        count:  (m['count']  as int?)    ?? 1,
      );

  Map<String, dynamic> toMap() =>
      {'name': name, 'dosage': dosage, 'form': form, 'count': count};

  String get displayLabel {
    final parts = <String>[name];
    if (dosage.isNotEmpty) parts.add(dosage);
    if (form.isNotEmpty) parts.add(form);
    return parts.join(' · ');
  }
}

// ── Modèle zone enrichi ───────────────────────────────────────────────────────
class ZoneEntry {
  final int id;
  final String name;
  final int totalBoxes;
  final String status; // 'Done' | 'Pending'
  final String time;
  final List<ZoneMedEntry> meds;

  const ZoneEntry({
    required this.id,
    required this.name,
    required this.totalBoxes,
    required this.status,
    required this.time,
    required this.meds,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class SessionProvider extends ChangeNotifier {
  int? _sessionId;
  String _sessionLabel = '';
  String _sessionCode  = '';
  String _startedAt    = '';
  bool _loading = false;

  List<ZoneEntry> _zones = [];

  int?           get sessionId    => _sessionId;
  String         get sessionLabel => _sessionLabel;
  String         get sessionCode  => _sessionCode;
  String         get startedAt    => _startedAt;
  bool           get loading      => _loading;
  List<ZoneEntry> get zones       => _zones;

  int get totalBoxes =>
      _zones.where((z) => z.status == 'Done').fold(0, (s, z) => s + z.totalBoxes);
  int get doneZones  => _zones.where((z) => z.status == 'Done').length;

  // ── Init / load session ───────────────────────────────────────────────────

  Future<void> loadOrCreateSession(int userId) async {
    _loading = true;
    notifyListeners();

    final db     = DatabaseHelper();
    final dbConn = await db.database;

    List<Map<String, dynamic>> sessions = await dbConn.query(
      'inventory_sessions',
      where:     "status = 'active' AND user_id = ?",
      whereArgs: [userId],
      orderBy:   'started_at DESC',
      limit:     1,
    );

    int sessionId;
    if (sessions.isEmpty) {
      final now   = DateTime.now();
      final label = 'Session ${DateFormat('dd/MM/yyyy').format(now)}';
      final code  = 'INV-${DateFormat('yyyy-MMdd').format(now)}-${userId.toString().padLeft(3, '0')}';
      sessionId   = await dbConn.insert('inventory_sessions', {
        'user_id':      userId,
        'label':        label,
        'session_code': code,
        'status':       'active',
        'total_boxes':  0,
        'total_zones':  0,
        'started_at':   DateTime.now().toIso8601String(),
      });
      sessions = await dbConn.query(
          'inventory_sessions', where: 'id = ?', whereArgs: [sessionId]);
    } else {
      sessionId = sessions.first['id'] as int;
    }

    final session = sessions.first;
    _sessionId    = sessionId;
    _sessionLabel = session['label']        as String? ?? '';
    _sessionCode  = session['session_code'] as String? ?? 'INV-$sessionId';
    _startedAt    = session['started_at']   as String? ?? '';

    await _reloadZones();

    _loading = false;
    notifyListeners();
  }

  // ── Handle scan result (called from anywhere) ─────────────────────────────

  Future<void> handleScanResult(Map<String, dynamic> result) async {
    if (_sessionId == null) return;

    final String  zoneName  = result['zoneName'] as String? ?? 'Zone';
    final int     boxCount  = result['count']    as int?    ?? 0;

    // meds is List<Map> with keys: name, dosage, form, count
    // OR List<String> (legacy — name only)
    final List<ZoneMedEntry> medEntries = _parseMeds(result['meds']);

    final db     = DatabaseHelper();
    final dbConn = await db.database;

    // Find or create zone
    final existing = await dbConn.query(
      'scan_zones',
      where:     "session_id = ? AND LOWER(zone_name) = ?",
      whereArgs: [_sessionId, zoneName.toLowerCase()],
      limit:     1,
    );

    int zoneId;
    if (existing.isNotEmpty) {
      zoneId = existing.first['id'] as int;
      await dbConn.update(
        'scan_zones',
        {
          'total_boxes': boxCount,
          'status':      'done',
          'scanned_at':  DateTime.now().toIso8601String(),
        },
        where:     'id = ?',
        whereArgs: [zoneId],
      );
    } else {
      zoneId = await dbConn.insert('scan_zones', {
        'session_id':  _sessionId,
        'zone_name':   zoneName,
        'status':      'done',
        'boxes':       boxCount,
        'total_boxes': boxCount,
        'scanned_at':  DateTime.now().toIso8601String(),
      });
    }

    // Persist rich med entries
    await db.deleteZoneMedicines(zoneId);
    for (final entry in medEntries) {
      if (entry.name.trim().isNotEmpty) {
        await db.insertZoneMedicineRich(zoneId, entry);
      }
    }

    await _reloadZones();
    notifyListeners();
  }
  Future<void> addEmptyZone(String zoneName) async {
    if (_sessionId == null) return;
    final dbConn = await DatabaseHelper().database;

    // Check if zone with same name already exists
    final existing = await dbConn.query(
      'scan_zones',
      where: "session_id = ? AND LOWER(zone_name) = ?",
      whereArgs: [_sessionId, zoneName.toLowerCase()],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    await dbConn.insert('scan_zones', {
      'session_id':  _sessionId,
      'zone_name':   zoneName,
      'status':      'pending',
      'boxes':       0,
      'total_boxes': 0,
    });

    await _reloadZones();
    notifyListeners();
  }

  // ── Save / complete session ───────────────────────────────────────────────

  Future<void> saveSession() async {
    if (_sessionId == null) return;
    final dbConn = await DatabaseHelper().database;
    await dbConn.update(
      'inventory_sessions',
      {
        'status':      'completed',
        'total_boxes': totalBoxes,
        'total_zones': doneZones,
        'ended_at':    DateTime.now().toIso8601String(),
      },
      where:     'id = ?',
      whereArgs: [_sessionId],
    );
    // Reset so a fresh session is created next time
    _sessionId = null;
    _zones     = [];
    notifyListeners();
  }

  // ── Reload zones from DB ──────────────────────────────────────────────────

  Future<void> _reloadZones() async {
    if (_sessionId == null) return;
    final db     = DatabaseHelper();
    final dbConn = await db.database;

    final zoneRows = await dbConn.query(
      'scan_zones',
      where:     'session_id = ?',
      whereArgs: [_sessionId],
      orderBy:   'id ASC',
    );

    final List<ZoneEntry> built = [];
    for (final z in zoneRows) {
      final zoneId  = z['id'] as int;
      final medMaps = await db.getMedicinesRichForZone(zoneId);
      built.add(ZoneEntry(
        id:         zoneId,
        name:       z['zone_name']  as String,
        totalBoxes: z['total_boxes'] as int,
        status:     (z['status'] as String) == 'done' ? 'Done' : 'Pending',
        time:       z['scanned_at'] != null
                        ? DateFormat('hh:mm a')
                            .format(DateTime.parse(z['scanned_at'] as String))
                        : '',
        meds: medMaps.map(ZoneMedEntry.fromMap).toList(),
      ));
    }
    _zones = built;
  }

  // ── Edit a medicine name inside a zone ────────────────────────────────────

  Future<void> updateMedName(int zoneId, int medDbId, String newName) async {
    final dbConn = await DatabaseHelper().database;
    await dbConn.update(
      'zone_medicines',
      {'name': newName},
      where:     'id = ?',
      whereArgs: [medDbId],
    );
    await _reloadZones();
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<ZoneMedEntry> _parseMeds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) {
        if (e is Map<String, dynamic>) {
          return ZoneMedEntry(
            name:   (e['name']   as String?) ?? '',
            dosage: (e['dosage'] as String?) ?? '',
            form:   (e['form']   as String?) ?? '',
            count:  (e['count']  as int?)    ?? 1,
          );
        }
        // Legacy: plain string
        return ZoneMedEntry(name: e.toString(), dosage: '', form: '', count: 1);
      }).toList();
    }
    return [];
  }

  String get formattedStart {
    try { return DateFormat('hh:mm a').format(DateTime.parse(_startedAt)); }
    catch (_) { return '--'; }
  }

  String get formattedDate {
    try { return DateFormat('MMM dd, yyyy').format(DateTime.parse(_startedAt)); }
    catch (_) { return DateFormat('MMM dd, yyyy').format(DateTime.now()); }
  }

  String get duration {
    try {
      final diff = DateTime.now().difference(DateTime.parse(_startedAt));
      final m    = diff.inMinutes;
      return m < 60 ? '$m min' : '${diff.inHours}h ${m % 60}m';
    } catch (_) { return '—'; }
  }
}
