/// Structured result of OCR + parsing for one medicine box crop.
class OcrResult {
  /// Best-matched medicine name from the database, or null if no match.
  final String? matchedName;

  /// Matched medicine form/type (e.g. "COMPRIMÉ", "INJECTABLE"), or null.
  final String? form;

  /// Matched dosage string (e.g. "500 MG", "1 G / 5 ML"), or null.
  final String? dosage;

  /// Raw text extracted by ML Kit (useful for debugging).
  final String rawText;

  /// Levenshtein-based confidence score [0..1] for the name match.
  final double confidence;

  const OcrResult({
    this.matchedName,
    this.form,
    this.dosage,
    required this.rawText,
    this.confidence = 0.0,
  });

  bool get hasName => matchedName != null && matchedName!.isNotEmpty;
  bool get hasForm => form != null;
  bool get hasDosage => dosage != null;
}