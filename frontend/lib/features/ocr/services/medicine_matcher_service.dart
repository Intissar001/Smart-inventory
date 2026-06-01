import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/ocr_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MedicineMatcherService — v2 (production-grade)
//
// Architecture:
//   • load()              → parses JSON once, pre-builds token index
//   • parse(ocrText)      → full pipeline: clean → extract → match → score
//   • cleanText()         → public utility for preprocessing
//
// Matching strategy:
//   1. Preprocess OCR text (uppercase, accent-strip, noise removal)
//   2. Remove manufacturer words, dosage patterns, pharmaceutical forms
//   3. Build unigram + bigram + trigram token sets from cleaned text
//   4. Look up candidates via inverted index (fast)
//   5. Score each candidate: exact token hits + Levenshtein similarity
//   6. Apply confidence threshold — return null if no confident match
// ─────────────────────────────────────────────────────────────────────────────

class MedicineMatcherService {
  // ── State ─────────────────────────────────────────────────────────────────

  List<String> _names = [];
  Map<String, List<int>> _index = {};

  /// Pre-tokenised medicine names (cached after load for performance)
  final List<List<String>> _nameTokens = [];

  bool get isReady => _names.isNotEmpty;

  // ── Configuration ──────────────────────────────────────────────────────────

  /// Minimum similarity score [0..1] for a match to be accepted
  static const double _threshold = 0.72;

  /// Minimum confidence [0..1] reported in OcrResult
  static const double _minReportedConfidence = 0.55;

  // ── Blacklists ────────────────────────────────────────────────────────────

  /// Manufacturer names to strip before matching
  static const Set<String> _manufacturers = {
    'VIATRIS', 'KABI', 'BRAUN', 'MYLAN', 'SANDOZ', 'BIOGARAN', 'TEVA',
    'AGUETTANT', 'LAPROPHAN', 'SOTHEMA', 'NORMON', 'COOPER', 'ISIO',
    'RANBAXY', 'EBEWE', 'HOSPIRA', 'THYMOORGAN', 'ZENITH', 'PHARMED',
    'GALENICA', 'POLYMEDIC', 'LLORENTE', 'PROMOPHARM', 'PHARMA5',
    'PHARMA', 'ACCORD', 'NOVOPHARMA', 'GENPHARMA', 'WIN', 'RIM',
    'DBL', 'ICN', 'BELLON', 'BIODIM', 'BAXTER', 'FRESENIUS',
    'EVER', 'DEVA', 'JANSSEN', 'NATIVELLE', 'SP', 'SMB', 'GT',
    'EUROPE', 'FRANCE', 'MAROC', 'PHARMACHEMIE', 'NAPROD', 'PCH',
    'SUN', 'IVAX', 'PIERRE', 'FABRE',
  };

  /// Pharmaceutical form keywords to strip
  static const Set<String> _forms = {
    'COMPRIME', 'COMPRIMES', 'PELLICULE', 'PELLICULES', 'ENROBE', 'ENROBES',
    'EFFERVESCENT', 'DISPERSIBLE', 'ORODISPERSIBLE', 'SUBLINGUAL', 'SECABLE',
    'GASTRO', 'LIBERATION', 'PROLONGEE', 'RETARD', 'MODIFIE',
    'GELULE', 'GELULES', 'CAPSULE', 'CAPSULES', 'MOLLE', 'DURE',
    'SIROP', 'SOLUTION', 'SUSPENSION', 'BUVABLE', 'INJECTABLE',
    'PERFUSION', 'POUDRE', 'GRANULE', 'GRANULES', 'SACHET', 'SACHETS',
    'CREME', 'POMMADE', 'GEL', 'LOTION', 'PATCH', 'AEROSOL',
    'COLLYRE', 'GOUTTES', 'SUPPOSITOIRE', 'OVULE', 'LYOPHILISAT',
    'SERINGUE', 'AMPOULE', 'FLACON', 'TUBE', 'BOITE', 'PLAQUETTE',
    'INHALATION', 'SPRAY', 'PULVERISATION', 'USAGE', 'EXTERNE',
    'ORAL', 'ORALE', 'NASALE', 'OPHTALMIQUE', 'AURICULAIRE',
    'TRANSDERMIQUE', 'INTRAVEINEUX', 'INTRAMUSCULAIRE', 'SOUS', 'CUTANE',
    'MODIFICATEUR', 'ACTION',
    'PEDIATRIQUE', 'ADULTE', 'NOURRISSON', 'ENFANT', 'NOURISSON',
  };

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    final raw = await rootBundle.loadString('assets/data/medicines_index.json');
    final Map<String, dynamic> json = jsonDecode(raw);

    _names = List<String>.from(json['names'] as List);

    final rawIndex = json['index'] as Map<String, dynamic>;
    _index = rawIndex.map(
      (k, v) => MapEntry(k, List<int>.from(v as List)),
    );

    // Pre-tokenise all medicine names once
    _nameTokens.clear();
    for (final name in _names) {
      _nameTokens.add(_tokenize(cleanText(name)));
    }

    debugPrint('[Matcher] Loaded ${_names.length} medicines.');
  }

  // ── Legacy API (kept for ocr_test_page.dart compatibility) ───────────────

  Future<void> loadMedicines() => load();

  OcrMedicineLegacy? findMedicine(String ocrText) {
    final result = parse(ocrText);
    if (!result.hasName) return null;
    return OcrMedicineLegacy(
      name: result.matchedName!,
      dosage: result.dosage,
      form: result.form,
    );
  }

  // ── Public entry point ────────────────────────────────────────────────────

  /// Full pipeline: raw OCR text → structured OcrResult
  OcrResult parse(String ocrText) {
    // 1. Preserve original for debug output
    final String rawText = ocrText;

    // 2. Extract dosage and form BEFORE cleaning (they have specific patterns)
    final String normalizedForExtraction = _normalize(ocrText);
    final String? dosage = _extractDosage(normalizedForExtraction);
    final String? form = _extractForm(normalizedForExtraction);

    // 3. Clean the text for name matching
    final String cleaned = cleanText(ocrText);
    if (cleaned.isEmpty) {
      return OcrResult(rawText: rawText, confidence: 0.0);
    }

    // 4. Build n-gram token set from cleaned OCR
    final List<String> words = _tokenize(cleaned);
    final List<String> ngrams = _buildNgrams(words);

    if (words.isEmpty) {
      return OcrResult(rawText: rawText, dosage: dosage, form: form, confidence: 0.0);
    }

    // 5. Find candidates via inverted index
    final Map<int, double> scores = _scoreCandidates(words, ngrams, cleaned);

    // 6. Pick best match above threshold
    if (scores.isEmpty) {
      return OcrResult(rawText: rawText, dosage: dosage, form: form, confidence: 0.0);
    }

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final best = sorted.first;
    final double confidence = best.value;

    if (confidence < _minReportedConfidence) {
      debugPrint('[Matcher] No confident match. Best: ${_names[best.key]} @ ${confidence.toStringAsFixed(2)}');
      return OcrResult(rawText: rawText, dosage: dosage, form: form, confidence: 0.0);
    }

    final String matchedName = _names[best.key];
    debugPrint('[Matcher] Matched "$matchedName" @ ${confidence.toStringAsFixed(2)}');

    return OcrResult(
      matchedName: matchedName,
      form: form,
      dosage: dosage,
      rawText: rawText,
      confidence: confidence.clamp(0.0, 1.0),
    );
  }

  // ── Text Cleaning Pipeline ────────────────────────────────────────────────

  /// Public utility: full preprocessing for a text before matching.
  /// Steps: uppercase → accent-strip → remove dosage → remove forms →
  ///        remove manufacturers → strip noise → normalize spaces
  String cleanText(String text) {
    String t = _normalize(text);       // uppercase + accent strip + special chars
    t = _removeDosagePatterns(t);      // e.g. 500 MG, 1G/5ML
    t = _removeBlacklistedWords(t, _forms);         // pharmaceutical forms
    t = _removeBlacklistedWords(t, _manufacturers); // manufacturer names
    t = _removeShortNoise(t);          // 1- or 2-char tokens
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // ── Normalization ─────────────────────────────────────────────────────────

  String _normalize(String text) {
    return text
        .toUpperCase()
        .replaceAll('À', 'A').replaceAll('Â', 'A').replaceAll('Ä', 'A')
        .replaceAll('Á', 'A').replaceAll('Ã', 'A')
        .replaceAll('È', 'E').replaceAll('É', 'E').replaceAll('Ê', 'E').replaceAll('Ë', 'E')
        .replaceAll('Ì', 'I').replaceAll('Í', 'I').replaceAll('Î', 'I').replaceAll('Ï', 'I')
        .replaceAll('Ò', 'O').replaceAll('Ó', 'O').replaceAll('Ô', 'O').replaceAll('Õ', 'O').replaceAll('Ö', 'O')
        .replaceAll('Ù', 'U').replaceAll('Ú', 'U').replaceAll('Û', 'U').replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C').replaceAll('Ñ', 'N')
        // Common OCR digit→letter confusions on medicine boxes
        .replaceAll('0', 'O').replaceAll('1', 'I').replaceAll('5', 'S')
        // Strip everything except letters, spaces, hyphens (keep hyphens for multi-word names)
        .replaceAll(RegExp(r'[^A-Z\s\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Remove dosage patterns like "500 MG", "1G", "10MG/ML", "250 MCG"
  String _removeDosagePatterns(String text) {
    return text
        .replaceAll(
          RegExp(
            r'\d+[\d\s,\.]*\s*(?:MBQ|GBQ|NMOL|MMOL|MUI|MCG|MG\/ML|MG\/G|G\/ML|UI\/ML|MG|ML|UI|IE|UG|GR|G|%)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Remove exact blacklisted words (whole-word matching)
  String _removeBlacklistedWords(String text, Set<String> blacklist) {
    final words = text.split(' ');
    return words.where((w) => !blacklist.contains(w)).join(' ');
  }

  /// Remove 1-2 character tokens (OCR noise)
  String _removeShortNoise(String text) {
    final words = text.split(' ');
    return words.where((w) => w.length >= 3).join(' ');
  }

  // ── Tokenization & N-grams ────────────────────────────────────────────────

  List<String> _tokenize(String text) =>
      text.split(RegExp(r'[\s\-]+')).where((w) => w.length >= 3).toList();

  /// Build unigrams + bigrams + trigrams from word list
  List<String> _buildNgrams(List<String> words) {
    final List<String> ngrams = List.from(words);

    // Bigrams
    for (int i = 0; i < words.length - 1; i++) {
      ngrams.add('${words[i]} ${words[i + 1]}');
    }

    // Trigrams
    for (int i = 0; i < words.length - 2; i++) {
      ngrams.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
    }

    return ngrams;
  }

  // ── Candidate Scoring ─────────────────────────────────────────────────────

  /// Returns a map of {nameIndex → confidence score}
  Map<int, double> _scoreCandidates(
    List<String> words,
    List<String> ngrams,
    String cleanedFull,
  ) {
    // Step 1: collect candidate indices via inverted index (fast pre-filter)
    final Map<int, int> hitCount = {};

    for (final w in words) {
      if (w.length < 3) continue;

      // Direct lookup
      _addHits(hitCount, _index[w], 2);

      // OCR variants (digit/letter substitutions reversed)
      for (final variant in _ocrVariants(w)) {
        _addHits(hitCount, _index[variant], 1);
      }
    }

    // Also search with bigrams/trigrams in the index
    for (final ng in ngrams) {
      if (ng.contains(' ')) {
        final parts = ng.split(' ');
        // Intersect candidate sets for multi-word names
        final Set<int>? common = _intersectCandidates(parts);
        if (common != null) {
          for (final idx in common) {
            hitCount[idx] = (hitCount[idx] ?? 0) + parts.length;
          }
        }
      }
    }

    if (hitCount.isEmpty) return {};

    // Step 2: Take top-30 by hit count, score them with Levenshtein
    final topCandidates = hitCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<int, double> scores = {};

    for (final entry in topCandidates.take(30)) {
      final int idx = entry.key;
      final String name = _names[idx];
      final List<String> nameWords = _nameTokens[idx];

      // Fast check: exact substring
      if (cleanedFull.contains(name)) {
        scores[idx] = 1.0;
        continue;
      }

      final double score = _computeScore(nameWords, words, cleanedFull, name);
      if (score >= _minReportedConfidence) {
        scores[idx] = score;
      }
    }

    return scores;
  }

  Set<int>? _intersectCandidates(List<String> parts) {
    Set<int>? result;
    for (final p in parts) {
      final hits = _index[p];
      if (hits == null) return null;
      final set = hits.toSet();
      result = result == null ? set : result.intersection(set);
      if (result.isEmpty) return null;
    }
    return result;
  }

  void _addHits(Map<int, int> hitCount, List<int>? hits, int weight) {
    if (hits == null) return;
    for (final idx in hits) {
      hitCount[idx] = (hitCount[idx] ?? 0) + weight;
    }
  }

  /// Multi-signal scoring for a single candidate name against OCR words
  double _computeScore(
    List<String> nameWords,
    List<String> ocrWords,
    String cleanedFull,
    String name,
  ) {
    final significant = nameWords.where((w) => w.length >= 3).toList();
    if (significant.isEmpty) return 0.0;

    int exactHits = 0;
    double simSum = 0.0;

    for (final nw in significant) {
      double bestSim = 0.0;
      bool exact = false;

      for (final ow in ocrWords) {
        if (ow.length < 3) continue;

        if (ow == nw) {
          bestSim = 1.0;
          exact = true;
          break;
        }

        final double sim = _levenshteinSimilarity(nw, ow);
        if (sim > bestSim) bestSim = sim;
      }

      if (exact) exactHits++;
      if (bestSim >= 0.75) simSum += bestSim;
    }

    if (simSum == 0.0) return 0.0;

    final double coverage = simSum / significant.length;
    final double exactBonus = exactHits / significant.length * 0.2;

    // Penalise very short names that match common substrings (false positives)
    final double lengthPenalty = name.length < 4 ? 0.5 : 1.0;

    return ((coverage + exactBonus) * lengthPenalty).clamp(0.0, 1.0);
  }

  // ── Dosage Extraction ─────────────────────────────────────────────────────

  static const List<String> _dosageUnits = [
    'MBQ', 'GBQ', 'NMOL', 'MMOL', 'MUI', 'MCG',
    'MG/ML', 'MG/G', 'G/ML', 'UI/ML',
    'MG', 'ML', 'UI', 'IE', 'UG', 'G', '%',
  ];

  String? _extractDosage(String text) {
    final unitPattern = _dosageUnits.map(RegExp.escape).join('|');
    final re = RegExp(
      r'(\d[\d,\.]*\s*(?:' + unitPattern + r')(?:\s*/\s*\d[\d,\.]*\s*(?:' + unitPattern + r'))*)',
      caseSensitive: false,
    );
    final match = re.firstMatch(text);
    if (match == null) return null;
    return match.group(0)!.trim().toUpperCase();
  }

  // ── Form Extraction ───────────────────────────────────────────────────────

  static const List<_FormEntry> _formEntries = [
    _FormEntry('INJECTABLE', 'Injectable'),
    _FormEntry('PERFUSION', 'Perfusion'),
    _FormEntry('SERINGUE', 'Seringue pré-remplie'),
    _FormEntry('LYOPHILISAT', 'Lyophilisat'),
    _FormEntry('COMPRIME EFFERVESCENT', 'Comprimé effervescent'),
    _FormEntry('COMPRIME DISPERSIBLE', 'Comprimé dispersible'),
    _FormEntry('COMPRIME ORODISPERSIBLE', 'Comprimé orodispersible'),
    _FormEntry('COMPRIME SUBLINGUAL', 'Comprimé sublingual'),
    _FormEntry('COMPRIME A CROQUER', 'Comprimé à croquer'),
    _FormEntry('COMPRIME A LIBERATION', 'Comprimé LP'),
    _FormEntry('COMPRIME GASTRO', 'Comprimé gastro-résistant'),
    _FormEntry('COMPRIMES PELLICULES', 'Comprimé pelliculé'),
    _FormEntry('COMPRIME PELLICULE', 'Comprimé pelliculé'),
    _FormEntry('COMPRIME SECABLE', 'Comprimé sécable'),
    _FormEntry('COMPRIME ENROBE', 'Comprimé enrobé'),
    _FormEntry('COMPRIME', 'Comprimé'),
    _FormEntry('GELULE A LIBERATION', 'Gélule LP'),
    _FormEntry('GELULE GASTRO', 'Gélule gastro-résistante'),
    _FormEntry('GELULE', 'Gélule'),
    _FormEntry('CAPSULE MOLLE', 'Capsule molle'),
    _FormEntry('CAPSULE', 'Capsule'),
    _FormEntry('SIROP', 'Sirop'),
    _FormEntry('SUSPENSION BUVABLE', 'Suspension buvable'),
    _FormEntry('SOLUTION BUVABLE', 'Solution buvable'),
    _FormEntry('POUDRE POUR SUSPENSION', 'Poudre susp. buvable'),
    _FormEntry('SACHET', 'Sachet'),
    _FormEntry('GRANULE', 'Granulé'),
    _FormEntry('CREME', 'Crème'),
    _FormEntry('POMMADE', 'Pommade'),
    _FormEntry('LOTION', 'Lotion'),
    _FormEntry('PATCH', 'Patch transdermique'),
    _FormEntry('AEROSOL', 'Aérosol / Inhaler'),
    _FormEntry('INHALATION', 'Inhalation'),
    _FormEntry('COLLYRE', 'Collyre'),
    _FormEntry('AEROSOL NASAL', 'Spray nasal'),
    _FormEntry('SUPPOSITOIRE', 'Suppositoire'),
    _FormEntry('OVULE', 'Ovule vaginal'),
  ];

  String? _extractForm(String text) {
    for (final entry in _formEntries) {
      if (text.contains(entry.keyword)) return entry.display;
    }
    return null;
  }

  // ── OCR Variant Generation ────────────────────────────────────────────────

  List<String> _ocrVariants(String word) {
    final variants = <String>[];
    if (word.contains('O')) variants.add(word.replaceAll('O', '0'));
    if (word.contains('I')) variants.add(word.replaceAll('I', '1'));
    if (word.contains('S')) variants.add(word.replaceAll('S', '5'));
    // Reverse substitutions: maybe OCR read a digit as a letter
    if (word.contains('0')) variants.add(word.replaceAll('0', 'O'));
    if (word.contains('1')) variants.add(word.replaceAll('1', 'I'));
    return variants;
  }

  // ── Levenshtein Similarity ────────────────────────────────────────────────

  double _levenshteinSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final int la = a.length, lb = b.length;
    // Quick length filter
    if ((la - lb).abs() > (la > lb ? la : lb) * 0.45) return 0.0;

    List<int> prev = List.generate(lb + 1, (j) => j);
    List<int> curr = List.filled(lb + 1, 0);

    for (int i = 1; i <= la; i++) {
      curr[0] = i;
      for (int j = 1; j <= lb; j++) {
        if (a[i - 1] == b[j - 1]) {
          curr[j] = prev[j - 1];
        } else {
          curr[j] = 1 +
              [prev[j], curr[j - 1], prev[j - 1]]
                  .reduce((x, y) => x < y ? x : y);
        }
      }
      final tmp = prev; prev = curr; curr = tmp;
    }

    final dist = prev[lb];
    final maxLen = la > lb ? la : lb;
    return 1.0 - dist / maxLen;
  }

  // ── Debug helper ──────────────────────────────────────────────────────────

  void debugPrint(String msg) {
    // ignore: avoid_print
    print(msg);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy shim — keeps ocr_test_page.dart compiling without changes
// ─────────────────────────────────────────────────────────────────────────────

class OcrMedicineLegacy {
  final String name;
  final String? dosage;
  final String? form;
  const OcrMedicineLegacy({required this.name, this.dosage, this.form});

  String get displayDosage => dosage?.isNotEmpty == true ? dosage! : '-';
  String get displayForm => form?.isNotEmpty == true ? form! : '-';
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _FormEntry {
  final String keyword;
  final String display;
  const _FormEntry(this.keyword, this.display);
}