import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/ocr_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MedicineMatcherService — v3
//
// What changed vs v2:
//   • Pharmaceutical forms are now loaded from
//     assets/data/formes_pharmaceutiques.json  (no more hardcoded list)
//   • Form matching uses FUZZY Levenshtein sliding-window search so that
//     OCR errors (1-2 wrong letters) still find the right form.
//   • The rest of the pipeline (name matching) is unchanged.
//
// Form matching algorithm:
//   For each phrase in the JSON list:
//     1. Normalize it (uppercase + accent-strip) — same pipeline as OCR text.
//     2. Split the OCR text into overlapping windows of the same word-count.
//     3. Compute Levenshtein similarity between the phrase and each window.
//     4. Accept the best match if similarity ≥ _formThreshold.
//   Multi-word phrases (e.g. "COMPRIME PELLICULE") are tried before shorter
//   ones so they win over a partial single-word match.
// ─────────────────────────────────────────────────────────────────────────────

class MedicineMatcherService {
  // ── State ─────────────────────────────────────────────────────────────────

  List<String> _names = [];
  Map<String, List<int>> _index = {};
  final List<List<String>> _nameTokens = [];

  /// Loaded from formes_pharmaceutiques.json:
  /// List of (normalizedPhrase, displayLabel, wordCount) tuples, sorted
  /// longest-phrase-first so longer matches win.
  final List<_FormEntry> _formEntries = [];

  /// Loaded from dosage_complet.json (values_with_units list):
  /// Sorted longest-phrase-first for greedy matching.
  final List<_DosageEntry> _dosageEntries = [];

  bool get isReady => _names.isNotEmpty;

  // ── Configuration ──────────────────────────────────────────────────────────

  static const double _threshold = 0.72;
  static const double _minReportedConfidence = 0.55;

  /// Minimum fuzzy similarity to accept a form match [0..1].
  /// 0.82 means up to ~2 wrong characters in a typical 12-char word.
  static const double _formThreshold = 0.82;

  // ── Blacklists ────────────────────────────────────────────────────────────

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
    // 1. Load medicine index
    final raw = await rootBundle.loadString('assets/data/medicines_index.json');
    final Map<String, dynamic> json = jsonDecode(raw);

    _names = List<String>.from(json['names'] as List);

    final rawIndex = json['index'] as Map<String, dynamic>;
    _index = rawIndex.map(
      (k, v) => MapEntry(k, List<int>.from(v as List)),
    );

    _nameTokens.clear();
    for (final name in _names) {
      _nameTokens.add(_tokenize(cleanText(name)));
    }

    // 2. Load pharmaceutical forms from JSON
    await _loadFormEntries();

    // 3. Load dosage patterns from JSON
    await _loadDosageEntries();

    debugPrint('[Matcher] Loaded ${_names.length} medicines, ${_formEntries.length} form phrases, ${_dosageEntries.length} dosage patterns.');
  }

  /// Parses formes_pharmaceutiques.json and builds the sorted _formEntries list.
  Future<void> _loadFormEntries() async {
    _formEntries.clear();
    try {
      final raw = await rootBundle.loadString('assets/formes_pharmaceutiques.json');
      final List<dynamic> phrases = jsonDecode(raw) as List<dynamic>;

      for (final phrase in phrases) {
        final String raw = (phrase as String).trim();
        if (raw.isEmpty) continue;

        // Normalize the phrase exactly like we normalize OCR text
        final String normalized = _normalizePlain(raw);
        if (normalized.isEmpty) continue;

        final int wordCount = normalized.split(RegExp(r'\s+')).length;

        _formEntries.add(_FormEntry(
          keyword: normalized,
          display: _toTitleCaseFrench(raw),
          wordCount: wordCount,
        ));
      }

      // Sort: longest phrases first (multi-word beats single-word)
      _formEntries.sort((a, b) => b.wordCount.compareTo(a.wordCount));
    } catch (e) {
      debugPrint('[Matcher] Warning: could not load formes_pharmaceutiques.json — $e');
      // Fall back to a minimal built-in list so the app doesn't break
      _formEntries.addAll(_builtinForms());
    }
  }

  /// Parses dosage_complet.json and builds the sorted _dosageEntries list.
  /// Only the "values_with_units" array is used for matching.
  Future<void> _loadDosageEntries() async {
    _dosageEntries.clear();
    try {
      final raw = await rootBundle.loadString('assets/dosage_complet.json');
      final Map<String, dynamic> jsonMap = jsonDecode(raw);

      final List<dynamic> values =
          (jsonMap['values_with_units'] as List<dynamic>? ?? []);

      for (final v in values) {
        final String original = (v as String).trim();
        if (original.isEmpty) continue;

        // Normalize: keep digits, letters, common dosage symbols
        final String normalized = _normalizeDosage(original);
        if (normalized.isEmpty) continue;

        final int wc = normalized.split(RegExp(r'\s+')).length;

        _dosageEntries.add(_DosageEntry(
          keyword: normalized,
          display: original,
          wordCount: wc,
        ));
      }

      // Sort longest-first so "500 MG / 5 ML" wins over "500 MG"
      _dosageEntries.sort((a, b) {
        final lenCmp = b.keyword.length.compareTo(a.keyword.length);
        return lenCmp != 0 ? lenCmp : b.wordCount.compareTo(a.wordCount);
      });
    } catch (e) {
      debugPrint('[Matcher] Warning: could not load dosage_complet.json — $e');
      // App keeps working; _extractDosage falls back to regex only.
    }
  }

  // ── Legacy API ────────────────────────────────────────────────────────────

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

  OcrResult parse(String ocrText) {
    final String rawText = ocrText;

    // Dosage: pass the raw OCR text — _extractDosage normalises internally
    // using _normalizeDosage (which keeps digits) for JSON matching, and
    // falls back to _normalizePlain for the regex pass.
    final String? dosage = _extractDosage(ocrText);

    // Form uses full normalization (digit sub included) — form words never
    // contain meaningful digits.
    final String normalizedForExtraction = _normalize(ocrText);
    final String? form = _extractForm(normalizedForExtraction);

    final String cleaned = cleanText(ocrText);
    if (cleaned.isEmpty) {
      return OcrResult(rawText: rawText, confidence: 0.0);
    }

    final List<String> words = _tokenize(cleaned);
    final List<String> ngrams = _buildNgrams(words);

    if (words.isEmpty) {
      return OcrResult(rawText: rawText, dosage: dosage, form: form, confidence: 0.0);
    }

    final Map<int, double> scores = _scoreCandidates(words, ngrams, cleaned);

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

  String cleanText(String text) {
    String t = _normalize(text);
    t = _removeDosagePatterns(t);
    t = _removeBlacklistedWords(t, _forms);
    t = _removeBlacklistedWords(t, _manufacturers);
    t = _removeShortNoise(t);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // ── Normalization ─────────────────────────────────────────────────────────

  /// Full OCR normalization: uppercase + accent-strip + digit substitutions
  String _normalize(String text) {
    return _normalizePlain(text)
        // Common OCR digit→letter confusions on medicine boxes
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('5', 'S');
  }

  /// Plain normalization without digit substitution — used for form phrases
  /// (form phrases don't have digit confusions so we skip that step)
  String _normalizePlain(String text) {
    return text
        .toUpperCase()
        .replaceAll('À', 'A').replaceAll('Â', 'A').replaceAll('Ä', 'A')
        .replaceAll('Á', 'A').replaceAll('Ã', 'A')
        .replaceAll('È', 'E').replaceAll('É', 'E').replaceAll('Ê', 'E').replaceAll('Ë', 'E')
        .replaceAll('Ì', 'I').replaceAll('Í', 'I').replaceAll('Î', 'I').replaceAll('Ï', 'I')
        .replaceAll('Ò', 'O').replaceAll('Ó', 'O').replaceAll('Ô', 'O').replaceAll('Õ', 'O').replaceAll('Ö', 'O')
        .replaceAll('Ù', 'U').replaceAll('Ú', 'U').replaceAll('Û', 'U').replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C').replaceAll('Ñ', 'N')
        .replaceAll(RegExp(r'[^A-Z\s\-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

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

  String _removeBlacklistedWords(String text, Set<String> blacklist) {
    final words = text.split(' ');
    return words.where((w) => !blacklist.contains(w)).join(' ');
  }

  String _removeShortNoise(String text) {
    final words = text.split(' ');
    return words.where((w) => w.length >= 3).join(' ');
  }

  // ── Tokenization & N-grams ────────────────────────────────────────────────

  List<String> _tokenize(String text) =>
      text.split(RegExp(r'[\s\-]+')).where((w) => w.length >= 3).toList();

  List<String> _buildNgrams(List<String> words) {
    final List<String> ngrams = List.from(words);
    for (int i = 0; i < words.length - 1; i++) {
      ngrams.add('${words[i]} ${words[i + 1]}');
    }
    for (int i = 0; i < words.length - 2; i++) {
      ngrams.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
    }
    return ngrams;
  }

  // ── Candidate Scoring ─────────────────────────────────────────────────────

  Map<int, double> _scoreCandidates(
    List<String> words,
    List<String> ngrams,
    String cleanedFull,
  ) {
    final Map<int, int> hitCount = {};

    for (final w in words) {
      if (w.length < 3) continue;
      _addHits(hitCount, _index[w], 2);
      for (final variant in _ocrVariants(w)) {
        _addHits(hitCount, _index[variant], 1);
      }
    }

    for (final ng in ngrams) {
      if (ng.contains(' ')) {
        final parts = ng.split(' ');
        final Set<int>? common = _intersectCandidates(parts);
        if (common != null) {
          for (final idx in common) {
            hitCount[idx] = (hitCount[idx] ?? 0) + parts.length;
          }
        }
      }
    }

    if (hitCount.isEmpty) return {};

    final topCandidates = hitCount.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<int, double> scores = {};

    for (final entry in topCandidates.take(30)) {
      final int idx = entry.key;
      final String name = _names[idx];
      final List<String> nameWords = _nameTokens[idx];

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
    final double lengthPenalty = name.length < 4 ? 0.5 : 1.0;

    return ((coverage + exactBonus) * lengthPenalty).clamp(0.0, 1.0);
  }

  // ── Dosage Extraction — JSON-powered with regex fallback ─────────────────
  //
  // Strategy (two-pass):
  //   Pass 1 — JSON values_with_units (fuzzy sliding-window):
  //     Normalize the OCR text with _normalizeDosage (keeps digits + units),
  //     then slide a word-window of the same size as each dosage pattern over
  //     the OCR words. Accept the best match above _dosageThreshold.
  //     Longest patterns are tried first so "500 MG / 5 ML" beats "500 MG".
  //   Pass 2 — Regex fallback:
  //     If JSON pass found nothing, fall back to the original numeric regex.
  // ────────────────────────────────────────────────────────────────────────

  static const double _dosageThreshold = 0.88;

  static final RegExp _dosageKeepChars = RegExp(r'[^A-Z0-9\s\.,%/\+]');

  /// Normalize a string for dosage matching — keeps digits and dosage symbols.
  String _normalizeDosage(String text) {
    return text
        .toUpperCase()
        .replaceAll('À', 'A').replaceAll('Â', 'A').replaceAll('Ä', 'A')
        .replaceAll('Á', 'A').replaceAll('Ã', 'A')
        .replaceAll('È', 'E').replaceAll('É', 'E').replaceAll('Ê', 'E').replaceAll('Ë', 'E')
        .replaceAll('Ì', 'I').replaceAll('Í', 'I').replaceAll('Î', 'I').replaceAll('Ï', 'I')
        .replaceAll('Ò', 'O').replaceAll('Ó', 'O').replaceAll('Ô', 'O').replaceAll('Õ', 'O').replaceAll('Ö', 'O')
        .replaceAll('Ù', 'U').replaceAll('Ú', 'U').replaceAll('Û', 'U').replaceAll('Ü', 'U')
        .replaceAll('Ç', 'C').replaceAll('Ñ', 'N')
        .replaceAll('µ', 'MCG')
        .replaceAll(_dosageKeepChars, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _extractDosage(String rawOcrText) {
    // Pass 1 — JSON-powered fuzzy matching
    if (_dosageEntries.isNotEmpty) {
      final String normalizedOcr = _normalizeDosage(rawOcrText);
      final List<String> ocrWords = normalizedOcr
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();

      String? bestDisplay;
      double bestScore = 0.0;
      int bestLen = 0;

      for (final entry in _dosageEntries) {
        final int wc = entry.wordCount;
        if (ocrWords.length < wc) continue;

        double phraseScore = 0.0;

        for (int i = 0; i <= ocrWords.length - wc; i++) {
          final String window = ocrWords.sublist(i, i + wc).join(' ');
          final double sim = _levenshteinSimilarity(entry.keyword, window);
          if (sim > phraseScore) phraseScore = sim;
          if (phraseScore == 1.0) break;
        }

        if (phraseScore >= _dosageThreshold) {
          if (entry.keyword.length > bestLen ||
              (entry.keyword.length == bestLen && phraseScore > bestScore)) {
            bestScore = phraseScore;
            bestDisplay = entry.display;
            bestLen = entry.keyword.length;
            debugPrint('[Dosage] Match: "${entry.display}" score=${phraseScore.toStringAsFixed(3)}');
          }
        }
      }

      if (bestDisplay != null) return bestDisplay;
    }

    // Pass 2 — Regex fallback
    return _extractDosageRegex(rawOcrText);
  }

  static const List<String> _dosageUnits = [
    'MBQ', 'GBQ', 'NMOL', 'MMOL', 'MUI', 'MCG',
    'MG/ML', 'MG/G', 'G/ML', 'UI/ML',
    'MG', 'ML', 'UI', 'IE', 'UG', 'GR', 'G', '%',
  ];

  String? _extractDosageRegex(String text) {
    final String normalized = _normalizePlain(text);
    final unitPattern = _dosageUnits.map(RegExp.escape).join('|');
    final re = RegExp(
      r'(\d[\d,\.]*\s*(?:' + unitPattern + r')(?:\s*/\s*\d[\d,\.]*\s*(?:' + unitPattern + r'))*)',
      caseSensitive: false,
    );
    final match = re.firstMatch(normalized);
    if (match == null) return null;
    return match.group(0)!.trim().toUpperCase();
  }

  // ── Form Extraction — FUZZY ───────────────────────────────────────────────
  //
  // Strategy:
  //   For each form phrase (sorted longest-first so specific wins):
  //     • Build every consecutive word-window of the same length from OCR text
  //     • Compare phrase vs window with Levenshtein similarity
  //     • Also try exact substring match (fast path)
  //   Accept first phrase whose best window score ≥ _formThreshold.
  //
  // Why sliding window and not whole-text similarity?
  //   The form word(s) appear somewhere inside a longer OCR text.
  //   Comparing the full text would dilute the score badly.
  // ──────────────────────────────────────────────────────────────────────────

  String? _extractForm(String normalizedOcrText) {
    if (_formEntries.isEmpty) return null;

    // Split OCR into words once
    final List<String> ocrWords =
        normalizedOcrText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (ocrWords.isEmpty) return null;

    String? bestDisplay;
    double bestScore = 0.0;
    int bestWordCount = 0; // prefer longer phrases when scores are equal

    for (final entry in _formEntries) {
      final String phrase = entry.keyword; // already normalized
      final int wc = entry.wordCount;

      if (ocrWords.length < wc) continue;

      double phraseScore = 0.0;

      // ── Sliding window: compare phrase against every wc-word window ────────
      // Word-level windows prevent "GEL" from matching inside "GELULES".
      // Handles both exact (score=1.0) and fuzzy matches uniformly.
      for (int i = 0; i <= ocrWords.length - wc; i++) {
        final String window = ocrWords.sublist(i, i + wc).join(' ');
        final double sim = _levenshteinSimilarity(phrase, window);
        if (sim > phraseScore) phraseScore = sim;
        if (phraseScore == 1.0) break; // can't do better
      }

      // Accept if above threshold AND (better score OR same score but longer phrase)
      if (phraseScore >= _formThreshold) {
        if (phraseScore > bestScore ||
            (phraseScore == bestScore && wc > bestWordCount)) {
          bestScore = phraseScore;
          bestDisplay = entry.display;
          bestWordCount = wc;
          debugPrint('[Form] Match: "${entry.display}" score=${phraseScore.toStringAsFixed(3)}');
        }
      }
    }

    return bestDisplay;
  }

  // ── OCR Variant Generation ────────────────────────────────────────────────

  List<String> _ocrVariants(String word) {
    final variants = <String>[];
    if (word.contains('O')) variants.add(word.replaceAll('O', '0'));
    if (word.contains('I')) variants.add(word.replaceAll('I', '1'));
    if (word.contains('S')) variants.add(word.replaceAll('S', '5'));
    if (word.contains('0')) variants.add(word.replaceAll('0', 'O'));
    if (word.contains('1')) variants.add(word.replaceAll('1', 'I'));
    return variants;
  }

  // ── Levenshtein Similarity ────────────────────────────────────────────────

  double _levenshteinSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final int la = a.length, lb = b.length;
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
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }

    final dist = prev[lb];
    final maxLen = la > lb ? la : lb;
    return 1.0 - dist / maxLen;
  }

  // ── Title-case helper for display labels ─────────────────────────────────

  String _toTitleCaseFrench(String text) {
    // Keep the original capitalisation from the JSON (it's already good French)
    // Just capitalise the very first letter in case it's lowercase.
    if (text.isEmpty) return text;
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  // ── Built-in fallback forms (used if JSON fails to load) ─────────────────

  List<_FormEntry> _builtinForms() => [
    _FormEntry(keyword: 'INJECTABLE', display: 'Injectable', wordCount: 1),
    _FormEntry(keyword: 'COMPRIME', display: 'Comprimé', wordCount: 1),
    _FormEntry(keyword: 'GELULE', display: 'Gélule', wordCount: 1),
    _FormEntry(keyword: 'SIROP', display: 'Sirop', wordCount: 1),
    _FormEntry(keyword: 'SOLUTION', display: 'Solution', wordCount: 1),
    _FormEntry(keyword: 'POMMADE', display: 'Pommade', wordCount: 1),
    _FormEntry(keyword: 'CAPSULE', display: 'Capsule', wordCount: 1),
    _FormEntry(keyword: 'SUPPOSITOIRE', display: 'Suppositoire', wordCount: 1),
    _FormEntry(keyword: 'COLLYRE', display: 'Collyre', wordCount: 1),
    _FormEntry(keyword: 'PATCH', display: 'Patch', wordCount: 1),
  ];

  // ── Debug helper ──────────────────────────────────────────────────────────

  void debugPrint(String msg) {
    // ignore: avoid_print
    print(msg);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legacy shim
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
  final String keyword;   // normalized (uppercase, accent-stripped)
  final String display;   // human-readable label to show in UI
  final int wordCount;    // number of words in the phrase
  const _FormEntry({
    required this.keyword,
    required this.display,
    required this.wordCount,
  });
}

class _DosageEntry {
  final String keyword;   // normalized version for matching
  final String display;   // original string to display
  final int wordCount;    // number of tokens in the phrase
  const _DosageEntry({
    required this.keyword,
    required this.display,
    required this.wordCount,
  });
}