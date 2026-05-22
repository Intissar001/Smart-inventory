import 'package:flutter/material.dart';
import '../db/database_helper.dart';

class AlertModel {
  final int id;
  final int medicineId;
  final String name;
  final int quantity;
  final int minStock;
  final String category;
  final String severity;
  bool isRead;

  AlertModel({
    required this.id,
    required this.medicineId,
    required this.name,
    required this.quantity,
    required this.minStock,
    required this.category,
    required this.severity,
    this.isRead = false,
  });

  factory AlertModel.fromMap(Map<String, dynamic> map) {
    return AlertModel(
      id: map['id'] as int,
      medicineId: map['medicine_id'] as int,
      name: map['medicine_name'] as String,
      quantity: map['quantity'] as int,
      minStock: map['min_stock'] as int,
      category: map['category'] as String? ?? '',
      severity: map['severity'] as String,
      isRead: (map['is_read'] as int) == 1,
    );
  }
}

class AlertsProvider extends ChangeNotifier {
  List<AlertModel> _alerts = [];
  bool _isLoading = false;

  List<AlertModel> get alerts => _alerts;
  bool get isLoading => _isLoading;

  int get criticalCount => _alerts.where((a) => a.severity == 'critical').length;
  int get urgentCount => _alerts.where((a) => a.severity == 'urgent').length;
  int get warningCount => _alerts.where((a) => a.severity == 'warning').length;
  int get unreadCount => _alerts.where((a) => !a.isRead).length;

  Future<void> loadAlerts() async {
    _isLoading = true;
    notifyListeners();

    final db = DatabaseHelper.instance;
    final rows = await db.getAlerts();
    _alerts = rows.map((r) => AlertModel.fromMap(r)).toList();

    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshAlerts() async {
    final db = DatabaseHelper.instance;
    await db.refreshAlerts();
    await loadAlerts();
  }

  Future<void> markAllRead() async {
    final db = DatabaseHelper.instance;
    await db.markAllAlertsRead();
    for (final a in _alerts) {
      a.isRead = true;
    }
    notifyListeners();
  }
}
