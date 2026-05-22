import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

/// Thin wrapper around Google ML Kit Text Recognition.
///
/// • Uses a singleton [TextRecognizer] so the ML model is loaded once.
/// • [processBytes] accepts raw JPEG bytes (e.g. from the /crop endpoint).
/// • Call [disposeRecognizer] when the owning widget is torn down.
class OCRService {
  static final TextRecognizer _recognizer = TextRecognizer();

  // ── Legacy helper (kept for ocr_test_page.dart) ──────────────────────────

  Future<File> getImageFileFromAssets(String path) async {
    final byteData = await rootBundle.load(path);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/temp_asset.jpeg');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  Future<String> processImage(String assetPath) async {
    final file = await getImageFileFromAssets(assetPath);
    return _runOnFile(file);
  }

  // ── Main entry: process raw JPEG bytes from /crop ────────────────────────

  /// Saves [bytes] to a uniquely-named temp file, runs ML Kit OCR,
  /// and returns the concatenated plain text from all recognised blocks.
  /// [tag] is used to name the temp file so concurrent crops don't collide.
  Future<String> processBytes(Uint8List bytes, {String tag = 'crop'}) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/ocr_$tag.jpeg');
    await file.writeAsBytes(bytes, flush: true);
    return _runOnFile(file);
  }

  // ── Shared OCR runner ─────────────────────────────────────────────────────

  Future<String> _runOnFile(File file) async {
    final inputImage = InputImage.fromFile(file);
    final RecognizedText result = await _recognizer.processImage(inputImage);
    return result.blocks.map((b) => b.text.trim()).join('\n').trim();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  static void disposeRecognizer() => _recognizer.close();
}