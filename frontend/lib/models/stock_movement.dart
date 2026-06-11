class StockMovement {
  final int? id;
  final int medicineId;
  final int? sessionId;
  final String movementType; // scan_add, manual_add, manual_remove, adjustment, reset
  final int quantityBefore;
  final int quantityChange;
  final int quantityAfter;
  final String? reason;
  final DateTime movedAt;

  // Constantes pour movementType
  static const String typeScanAdd = 'scan_add';
  static const String typeManualAdd = 'manual_add';
  static const String typeManualRemove = 'manual_remove';
  static const String typeAdjustment = 'adjustment';
  static const String typeReset = 'reset';

  StockMovement({
    this.id,
    required this.medicineId,
    this.sessionId,
    required this.movementType,
    required this.quantityBefore,
    required this.quantityChange,
    required this.quantityAfter,
    this.reason,
    required this.movedAt,
  });

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id'] as int?,
      medicineId: map['medicine_id'] as int,
      sessionId: map['session_id'] as int?,
      movementType: map['movement_type'] as String,
      quantityBefore: map['quantity_before'] as int,
      quantityChange: map['quantity_change'] as int,
      quantityAfter: map['quantity_after'] as int,
      reason: map['reason'] as String?,
      movedAt: DateTime.parse(map['moved_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicine_id': medicineId,
      'session_id': sessionId,
      'movement_type': movementType,
      'quantity_before': quantityBefore,
      'quantity_change': quantityChange,
      'quantity_after': quantityAfter,
      'reason': reason,
      'moved_at': movedAt.toIso8601String(),
    };
  }
}