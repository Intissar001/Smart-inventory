// lib/models/scan_detection.dart
//
// Modèle représentant UNE détection individuelle par YOLO + OCR.
// Chaque boîte détectée dans une zone génère une ScanDetection.

class ScanDetection {
  final int?   id;
  final int    zoneId;
  final int?   medicineId;      // Lien vers medicines.id (NULL si non identifié)
  final String? rawOcrText;    // Texte brut retourné par Google ML Kit
  final String? matchedName;   // Nom après nettoyage + fuzzy matching
  final String? dosageDetected;
  final String? formDetected;
  final double  confidence;    // Score YOLO (0.0 – 1.0)
  final double  ocrConfidence; // Score fuzzy match (0.0 – 1.0)
  final int     quantity;      // Nombre de boîtes identiques comptées
  final String? cropImagePath; // Image croppée de la boîte (chemin local)
  final bool    isConfirmed;   // L'utilisateur a validé la détection
  final String? detectedAt;

  const ScanDetection({
    this.id,
    required this.zoneId,
    this.medicineId,
    this.rawOcrText,
    this.matchedName,
    this.dosageDetected,
    this.formDetected,
    this.confidence    = 0.0,
    this.ocrConfidence = 0.0,
    this.quantity      = 1,
    this.cropImagePath,
    this.isConfirmed   = false,
    this.detectedAt,
  });

  // ── SQLite ─────────────────────────────────────────────────

  factory ScanDetection.fromMap(Map<String, dynamic> map) => ScanDetection(
        id:              map['id'] as int?,
        zoneId:          map['zone_id'] as int,
        medicineId:      map['medicine_id'] as int?,
        rawOcrText:      map['raw_ocr_text'] as String?,
        matchedName:     map['matched_name'] as String?,
        dosageDetected:  map['dosage_detected'] as String?,
        formDetected:    map['form_detected'] as String?,
        confidence:      ((map['confidence'] as num?) ?? 0.0).toDouble(),
        ocrConfidence:   ((map['ocr_confidence'] as num?) ?? 0.0).toDouble(),
        quantity:        (map['quantity'] as int?) ?? 1,
        cropImagePath:   map['crop_image_path'] as String?,
        isConfirmed:     ((map['is_confirmed'] as int?) ?? 0) == 1,
        detectedAt:      map['detected_at'] as String?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'zone_id':          zoneId,
        'medicine_id':      medicineId,
        'raw_ocr_text':     rawOcrText,
        'matched_name':     matchedName,
        'dosage_detected':  dosageDetected,
        'form_detected':    formDetected,
        'confidence':       confidence,
        'ocr_confidence':   ocrConfidence,
        'quantity':         quantity,
        'crop_image_path':  cropImagePath,
        'is_confirmed':     isConfirmed ? 1 : 0,
      };

  // ── Helpers ────────────────────────────────────────────────

  /// Indique si la détection a un médicament reconnu
  bool get isIdentified => medicineId != null;

  /// Nom à afficher (préfère le nom matché, sinon le texte OCR brut)
  String get displayName => matchedName ?? rawOcrText ?? 'Médicament inconnu';

  ScanDetection copyWith({
    int?    id,
    int?    medicineId,
    String? matchedName,
    String? dosageDetected,
    String? formDetected,
    double? confidence,
    double? ocrConfidence,
    int?    quantity,
    String? cropImagePath,
    bool?   isConfirmed,
  }) =>
      ScanDetection(
        id:              id              ?? this.id,
        zoneId:          zoneId,
        medicineId:      medicineId      ?? this.medicineId,
        rawOcrText:      rawOcrText,
        matchedName:     matchedName     ?? this.matchedName,
        dosageDetected:  dosageDetected  ?? this.dosageDetected,
        formDetected:    formDetected    ?? this.formDetected,
        confidence:      confidence      ?? this.confidence,
        ocrConfidence:   ocrConfidence   ?? this.ocrConfidence,
        quantity:        quantity        ?? this.quantity,
        cropImagePath:   cropImagePath   ?? this.cropImagePath,
        isConfirmed:     isConfirmed     ?? this.isConfirmed,
        detectedAt:      detectedAt,
      );

  @override
  String toString() =>
      'ScanDetection(id: $id, name: $displayName, qty: $quantity, conf: ${(confidence * 100).round()}%)';
}
