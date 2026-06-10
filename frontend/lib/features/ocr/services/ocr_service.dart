import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'image_preprocessor.dart';   // ← the new file

// ─────────────────────────────────────────────────────────────────────────────
// Internal: word + its visual size score
// ─────────────────────────────────────────────────────────────────────────────
class _WordEntry {
  final String word;
  final double height;   // bounding-box height in pixels
  final double area;     // bounding-box area (width × height)

  const _WordEntry({
    required this.word,
    required this.height,
    required this.area,
  });

  // Score = height is primary, area is tiebreaker
  double get score => height * 1000 + area;
}

// ─────────────────────────────────────────────────────────────────────────────
// Public result type
// ─────────────────────────────────────────────────────────────────────────────
class OcrRawResult {
  final String fullText;
  final String? largestText;   // word with the biggest bounding box
  final List<String> topWords; // top-5 by size, for debugging
  const OcrRawResult({
    required this.fullText,
    this.largestText,
    this.topWords = const [],
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// OCR Service — v5
//
// Changes vs v4:
//   • processBytesRich() and processBytes() now run ImagePreprocessor.process()
//     before passing the image to ML Kit.
//   • Preprocessing is skipped for very large images (> kMaxPreprocessArea px²)
//     where the original is already high-resolution — we'd only waste time.
//   • A PreprocessResult diagnostic is printed at debug level.
//   • All existing logic (cornerPoints, line-level fallback, deduplication) is
//     preserved unchanged.
// ─────────────────────────────────────────────────────────────────────────────
class OCRService {
  static final TextRecognizer _recognizer = TextRecognizer();

  // Skip preprocessing for images whose area exceeds this.
  // 1200×900 = 1 080 000 → already high-res, ML Kit will do fine.
static const int _kMaxPreprocessArea = 1080000;
  // ── Legacy ────────────────────────────────────────────────────────────────
  Future<File> getImageFileFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_asset.jpeg');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  Future<String> processImage(String assetPath) async {
    final file = await getImageFileFromAssets(assetPath);
    final r = await _runOnFile(file);
    return r.fullText;
  }

  // ── Main entry ────────────────────────────────────────────────────────────

  /// Rich entry point used by ScanResultsScreen.
  /// Applies preprocessing before ML Kit if the crop is small or degraded.
  Future<OcrRawResult> processBytesRich(Uint8List bytes,
      {String tag = 'crop'}) async {
    final Uint8List processedBytes = await _maybePreprocess(bytes, tag: tag);

    final tempDir = await getTemporaryDirectory();
    final file = File(
        '${tempDir.path}/ocr_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpeg');
    await file.writeAsBytes(processedBytes, flush: true);
    try {
      return await _runOnFile(file);
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<String> processBytes(Uint8List bytes, {String tag = 'crop'}) async {
    final r = await processBytesRich(bytes, tag: tag);
    return r.fullText;
  }

  // ── Preprocessing gate ────────────────────────────────────────────────────

  /// Runs ImagePreprocessor.process() unless the image is already large.
  /// Returns the (possibly enhanced) bytes to feed to ML Kit.
  Future<Uint8List> _maybePreprocess(Uint8List bytes, {String tag = 'crop'}) async {
    // Quick size check from JPEG SOF0 header (avoids full decode)
    final _QuickSize? qs = _quickJpegSize(bytes);
    if (qs != null) {
      final int area = qs.width * qs.height;
      if (area > _kMaxPreprocessArea) {
        debugPrint('[OCR-$tag] Skipping preprocess — image already large '
            '(${qs.width}×${qs.height}, area=$area)');
        return bytes;
      }
    }

    try {
      final PreprocessResult result = await ImagePreprocessor.process(bytes);
      debugPrint('[OCR-$tag] $result');
      return result.bytes;
    } catch (e) {
      debugPrint('[OCR-$tag] Preprocessor error: $e — using original bytes');
      return bytes;
    }
  }

  /// Reads width/height from a JPEG SOF0 marker without full decode.
  /// Returns null if the bytes are not a recognisable JPEG or SOF0 is absent.
  _QuickSize? _quickJpegSize(Uint8List bytes) {
    try {
      int i = 2; // skip SOI (FFD8)
      while (i < bytes.length - 3) {
        if (bytes[i] != 0xFF) break;
        final int marker = bytes[i + 1];
        final int segLen = (bytes[i + 2] << 8) | bytes[i + 3];
        if (marker == 0xC0 || marker == 0xC2) {
          // SOF0 / SOF2 — height at +5, width at +7
          if (i + 8 < bytes.length) {
            final int h = (bytes[i + 5] << 8) | bytes[i + 6];
            final int w = (bytes[i + 7] << 8) | bytes[i + 8];
            return _QuickSize(w, h);
          }
        }
        i += 2 + segLen;
      }
    } catch (_) {}
    return null;
  }

  // ── Core ──────────────────────────────────────────────────────────────────
  Future<OcrRawResult> _runOnFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final RecognizedText recognized =
        await _recognizer.processImage(inputImage);
    return _buildResult(recognized);
  }

  OcrRawResult _buildResult(RecognizedText recognized) {
    final List<String> lines = [];
    final List<_WordEntry> entries = [];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final String trimmed = line.text.trim();
        if (!_isUsefulLine(trimmed)) continue;
        lines.add(trimmed);

        // ── Element level (individual words) ─────────────────────────────
        for (final element in line.elements) {
          final String word = element.text.trim();
          if (!_isGoodCandidate(word)) continue;

          // Method 1: use cornerPoints to get the TRUE height
          // cornerPoints = [topLeft, topRight, bottomRight, bottomLeft]
          final pts = element.cornerPoints;
          double elHeight = 0;
          double elWidth = 0;

          if (pts != null && pts.length == 4) {
            // Height = average of left-side height and right-side height
            final leftH = _dist(pts[0], pts[3]);
            final rightH = _dist(pts[1], pts[2]);
            elHeight = (leftH + rightH) / 2;
            // Width = average of top-side width and bottom-side width
            final topW = _dist(pts[0], pts[1]);
            final bottomW = _dist(pts[3], pts[2]);
            elWidth = (topW + bottomW) / 2;
          } else {
            // Fallback: use boundingBox
            final bbox = element.boundingBox;
            if (bbox != null) {
              elHeight = bbox.height.toDouble();
              elWidth = bbox.width.toDouble();
            }
          }

          if (elHeight <= 0) continue;

          entries.add(_WordEntry(
            word: word,
            height: elHeight,
            area: elHeight * elWidth,
          ));
        }

        // ── Line level — single-word lines get an extra entry ─────────────
        // Reason: for lines like "TOSSEDYL" or "BLUMAG", ML Kit sometimes
        // gives a single element but the LINE bbox is more accurate.
        final wordCount = trimmed.split(RegExp(r'\s+')).length;
        if (wordCount == 1 && !_isNoiseWord(trimmed)) {
          final pts = line.cornerPoints;
          double lnH = 0, lnW = 0;
          if (pts != null && pts.length == 4) {
            lnH = (_dist(pts[0], pts[3]) + _dist(pts[1], pts[2])) / 2;
            lnW = (_dist(pts[0], pts[1]) + _dist(pts[3], pts[2])) / 2;
          } else {
            final bbox = line.boundingBox;
            if (bbox != null) {
              lnH = bbox.height.toDouble();
              lnW = bbox.width.toDouble();
            }
          }
          if (lnH > 0) {
            entries.add(_WordEntry(
              word: trimmed,
              height: lnH,
              area: lnH * lnW,
            ));
          }
        }
      }
    }

    final List<String> deduped = _deduplicateLines(lines);
    final String fullText = deduped.join('\n');

    if (entries.isEmpty) {
      return OcrRawResult(fullText: fullText);
    }

    // ── Pure argmax by score ───────────────────────────────────────────────
    entries.sort((a, b) => b.score.compareTo(a.score));

    // Debug: print top-5
    final top5 = entries
        .take(5)
        .map((e) =>
            '"${e.word}" h=${e.height.toStringAsFixed(1)} a=${e.area.toStringAsFixed(0)}')
        .toList();
    // ignore: avoid_print
    print('[OCR] TOP-5 by size: ${top5.join(' | ')}');

    final String largest = entries.first.word;
    final List<String> topWords = entries.take(5).map((e) => e.word).toList();

    return OcrRawResult(
      fullText: fullText,
      largestText: _toTitleCase(largest),
      topWords: topWords,
    );
  }

  // ── Euclidean distance between two corner points ──────────────────────────
  double _dist(Point<int> a, Point<int> b) {
    final dx = (a.x - b.x).toDouble();
    final dy = (a.y - b.y).toDouble();
    return sqrt(dx * dx + dy * dy);
  }

  // ── Candidate filter ──────────────────────────────────────────────────────
  bool _isGoodCandidate(String word) {
    if (word.length < 2) return false;
    // purely numeric
    if (RegExp(r'^\d+[\d\s\.\,\-\/]*$').hasMatch(word)) return false;
    // only symbols / punctuation
    if (RegExp(r'^[^a-zA-ZÀ-ÿ\u0600-\u06FF]+$').hasMatch(word)) return false;
    if (_isNoiseWord(word)) return false;
    return true;
  }

  bool _isUsefulLine(String line) {
    if (line.isEmpty || line.length < 2) return false;
    if (RegExp(r'^\d[\d\s\.\-\/]*$').hasMatch(line)) return false;
    if (RegExp(r'^[^a-zA-ZÀ-ÿ\u0600-\u06FF]+$').hasMatch(line)) return false;
    return true;
  }

  static const Set<String> _noiseWords = {
    'ML', 'MG', 'UI', 'MCG', 'GBQ', 'MBQ', 'GR',
    'LOT', 'EXP', 'REF', 'DCI',
    'DE', 'DU', 'LE', 'LA', 'LES', 'EN', 'ET', 'AU', 'AUX',
    'UN', 'UNE', 'DES', 'SUR', 'PAR', 'POUR',
    'SA', 'FR', 'MA', 'PC', 'NO',
    'ADULTES', 'ADULTE', 'ENFANT', 'ENFANTS', 'NOURRISSON',
  };

  bool _isNoiseWord(String w) => _noiseWords.contains(w.toUpperCase());

  List<String> _deduplicateLines(List<String> lines) {
    final List<String> result = [];
    for (final line in lines) {
      final String n = line.toUpperCase().trim();
      bool dup = false;
      for (final existing in result) {
        final String en = existing.toUpperCase().trim();
        if (en == n || (n.length > 4 && (en.contains(n) || n.contains(en)))) {
          dup = true;
          break;
        }
      }
      if (!dup) result.add(line);
    }
    return result;
  }

  String _toTitleCase(String text) {
    if (text.isEmpty) return text;
    if (text == text.toUpperCase()) {
      return text
          .split(' ')
          .map((w) =>
              w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
          .join(' ');
    }
    return text;
  }

  static void disposeRecognizer() => _recognizer.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helper
// ─────────────────────────────────────────────────────────────────────────────
class _QuickSize {
  final int width;
  final int height;
  const _QuickSize(this.width, this.height);
}