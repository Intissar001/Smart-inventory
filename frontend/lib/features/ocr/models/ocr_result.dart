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

  /// The visually largest text detected by ML Kit (fallback when no DB match).
  /// This is typically the brand name printed in large font on the box.
  final String? largestText;

  const OcrResult({
    this.matchedName,
    this.form,
    this.dosage,
    required this.rawText,
    this.confidence = 0.0,
    this.largestText,
  });

  /// The best name to display:
  ///   1. DB-matched name (confident)
  ///   2. Largest visual text on the box (fallback)
  ///   3. null
  String? get displayName => hasName ? matchedName : largestText;

  bool get hasName => matchedName != null && matchedName!.isNotEmpty;
  bool get hasForm => form != null;
  bool get hasDosage => dosage != null;
  bool get hasLargestText => largestText != null && largestText!.isNotEmpty;

  /// True when we are showing a fallback (not a DB match)
  bool get isFallback => !hasName && hasLargestText;
}