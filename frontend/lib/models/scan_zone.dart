class ScanZone {
  final int? id;
  final int sessionId;
  final String zoneName;
  final String status; // pending, done
  final int totalBoxes;
  final DateTime? scannedAt;
  final String? imagePath;
  final String? notes;

  ScanZone({
    this.id,
    required this.sessionId,
    required this.zoneName,
    required this.status,
    this.totalBoxes = 0,
    this.scannedAt,
    this.imagePath,
    this.notes,
  });

  factory ScanZone.fromMap(Map<String, dynamic> map) {
    return ScanZone(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      zoneName: map['zone_name'] as String,
      status: map['status'] as String,
      totalBoxes: map['total_boxes'] as int,
      scannedAt: map['scanned_at'] != null ? DateTime.parse(map['scanned_at'] as String) : null,
      imagePath: map['image_path'] as String?,
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'zone_name': zoneName,
      'status': status,
      'total_boxes': totalBoxes,
      'scanned_at': scannedAt?.toIso8601String(),
      'image_path': imagePath,
      'notes': notes,
    };
  }

  ScanZone copyWith({int? id, int? sessionId, String? zoneName, String? status, int? totalBoxes, DateTime? scannedAt, String? imagePath, String? notes}) {
    return ScanZone(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      zoneName: zoneName ?? this.zoneName,
      status: status ?? this.status,
      totalBoxes: totalBoxes ?? this.totalBoxes,
      scannedAt: scannedAt ?? this.scannedAt,
      imagePath: imagePath ?? this.imagePath,
      notes: notes ?? this.notes,
    );
  }
}