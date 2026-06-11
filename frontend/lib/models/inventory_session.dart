class InventorySession {
  final int? id;
  final int userId; // 👈 Nouveau champ requis
  final String label;
  final String status; // active, completed, cancelled
  final int totalBoxes;
  final int totalZones;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;

  InventorySession({
    this.id,
    required this.userId,
    required this.label,
    required this.status,
    this.totalBoxes = 0,
    this.totalZones = 0,
    required this.startedAt,
    this.endedAt,
    this.notes,
  });

  factory InventorySession.fromMap(Map<String, dynamic> map) {
    return InventorySession(
      id: map['id'] as int?,
      userId: map['user_id'] as int,
      label: map['label'] as String,
      status: map['status'] as String,
      totalBoxes: map['total_boxes'] as int,
      totalZones: map['total_zones'] as int,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: map['ended_at'] != null ? DateTime.parse(map['ended_at'] as String) : null,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'label': label,
      'status': status,
      'total_boxes': totalBoxes,
      'total_zones': totalZones,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'notes': notes,
    };
  }

  InventorySession copyWith({
    int? id,
    int? userId,
    String? label,
    String? status,
    int? totalBoxes,
    int? totalZones,
    DateTime? startedAt,
    DateTime? endedAt,
    String? notes,
  }) {
    return InventorySession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      label: label ?? this.label,
      status: status ?? this.status,
      totalBoxes: totalBoxes ?? this.totalBoxes,
      totalZones: totalZones ?? this.totalZones,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      notes: notes ?? this.notes,
    );
  }
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InventorySession && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}