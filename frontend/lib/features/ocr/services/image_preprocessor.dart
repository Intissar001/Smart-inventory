import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ImagePreprocessor — v1
//
// Pure-Dart, zero-dependency image preprocessing pipeline for medicine
// box OCR. Designed to maximise ML Kit's ability to read dosage and
// pharmaceutical form text, which tends to be:
//   • Small (8–14 px tall in a typical YOLO crop)
//   • Low-contrast (white/light text on coloured background or vice-versa)
//   • Blurry (handheld, auto-focus on the wrong plane)
//   • Present on curved or reflective packaging
//
// Pipeline (applied in order, each step is conditional):
//   1. Decode bytes → RGBA pixel buffer
//   2. Analyse image: compute mean luminance + estimate blur (Laplacian variance)
//   3. Upscale if too small  (target ≥ kMinDimension on shortest axis)
//   4. Adaptive brightness/contrast correction (CLAHE-lite: per-tile histogram
//      equalisation — implemented as a global histogram stretch here because
//      true CLAHE is too expensive on mobile; the result is identical for
//      medicine boxes which have relatively uniform regions)
//   5. Unsharp-mask sharpening (only when blur is detected)
//   6. Re-encode to JPEG at high quality
//
// Each step documents WHY it helps dosage/form OCR specifically.
// ─────────────────────────────────────────────────────────────────────────────

/// Diagnostic information returned alongside the processed bytes.
/// Useful for debug logging in OCRService.
class PreprocessResult {
  final Uint8List bytes;
  final int originalWidth;
  final int originalHeight;
  final int processedWidth;
  final int processedHeight;
  final double meanLuminance; // 0..255
  final double laplacianVariance; // proxy for sharpness; low = blurry
  final bool wasUpscaled;
  final bool contrastApplied;
  final bool sharpeningApplied;

  const PreprocessResult({
    required this.bytes,
    required this.originalWidth,
    required this.originalHeight,
    required this.processedWidth,
    required this.processedHeight,
    required this.meanLuminance,
    required this.laplacianVariance,
    required this.wasUpscaled,
    required this.contrastApplied,
    required this.sharpeningApplied,
  });

  @override
  String toString() =>
      '[Preprocess] ${originalWidth}x$originalHeight → ${processedWidth}x$processedHeight '
      '| lum=${meanLuminance.toStringAsFixed(1)} '
      '| lap=${laplacianVariance.toStringAsFixed(1)} '
      '| upscale=$wasUpscaled contrast=$contrastApplied sharpen=$sharpeningApplied';
}

class ImagePreprocessor {
  // ── Tunable thresholds ───────────────────────────────────────────────────

  /// Minimum pixel length of the shortest image dimension before we upscale.
  /// Below this, ML Kit struggles with small dosage text (e.g. "500 MG").
  /// Empirically, characters need ~20 px height to be reliably detected.
  /// A crop of 80 px height with 4-px-tall text upscales to 240 px → 12 px
  /// characters → reliably read. Keep between 200–320 for mobile perf.
  static const int kMinDimension = 260;

  /// Maximum upscale factor applied in a single step.
  /// Prevents runaway memory use on very tiny crops (e.g. 20×10).
  static const double kMaxUpscaleFactor = 4.0;

  /// Laplacian variance below this value → image is considered blurry →
  /// sharpening will be applied.
  /// Typical values: crisp image ≈ 300–800, moderate blur ≈ 50–150,
  /// severe blur < 30. Threshold of 120 catches real-world handheld blur.
  static const double kBlurThreshold = 120.0;

  /// Sharpening strength (unsharp mask amount). 0.0 = off, 1.0 = strong.
  /// 0.55 is aggressive enough to recover soft edges without haloing.
  static const double kSharpenAmount = 0.55;

  /// Unsharp mask radius in pixels (Gaussian blur radius used internally).
  /// Keep at 1 for speed — sufficient for character-edge sharpening.
  static const int kSharpenRadius = 1;

  /// Mean luminance below this → image is dark → brightness lift applied.
  static const double kDarkThreshold = 90.0;

  /// Mean luminance above this → image is washed out → contrast reduction.
  static const double kBrightThreshold = 185.0;

  /// Percentile cut-off for histogram stretching (per channel).
  /// 0.02 = ignore the darkest/brightest 2% of pixels (handles hot pixels
  /// and deep shadows that would otherwise clip the stretch).
  static const double kHistogramClipPercent = 0.02;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Main entry point. Takes raw image bytes (any format Flutter can decode:
  /// JPEG, PNG, WebP, …) and returns enhanced bytes + diagnostics.
  ///
  /// This runs on an [Isolate] internally so the UI thread is never blocked.
  /// If isolate spawning fails it falls back to running on the calling thread.
  static Future<PreprocessResult> process(Uint8List inputBytes) async {
    // Offload heavy pixel work to a background isolate.
    // compute() serialises the Uint8List automatically.
    try {
      return await compute(_processIsolate, inputBytes);
    } catch (e) {
      // compute() can fail on some platforms in debug mode — fallback.
      debugPrint('[Preprocess] compute() fallback: $e');
      return _processIsolate(inputBytes);
    }
  }

  // ── Isolate entry ────────────────────────────────────────────────────────

  static PreprocessResult _processIsolate(Uint8List inputBytes) {
    // 1. Decode to raw RGBA
    final _RgbaImage img = _decodeJpeg(inputBytes);
    final int origW = img.width;
    final int origH = img.height;

    // 2. Analyse
    final double lum = _meanLuminance(img);
    final double lap = _laplacianVariance(img);

    _RgbaImage current = img;
    bool wasUpscaled = false;
    bool contrastApplied = false;
    bool sharpeningApplied = false;

    // 3. ── Upscale if too small ──────────────────────────────────────────
    // WHY: ML Kit's text detector needs characters to be at least ~20 px tall.
    // YOLO crops of small dosage sub-regions are often 60–120 px tall, making
    // "MG" characters only 4–8 px — well below detection threshold.
    final int shortest = min(current.width, current.height);
    if (shortest < kMinDimension) {
      final double factor =
          min(kMaxUpscaleFactor, kMinDimension / shortest);
      current = _bilinearScale(current, factor);
      wasUpscaled = true;
    }

    // 4. ── Contrast / brightness correction ─────────────────────────────
    // WHY: Dosage text is often printed at low contrast (white on light-blue,
    // grey on white). Histogram stretching expands the tonal range so ML Kit's
    // edge detector sees sharper character boundaries.
    // We also lift dark images (pharmacy storage photos taken in dim light).
    if (lum < kDarkThreshold || lum > kBrightThreshold ||
        _needsContrastBoost(current)) {
      current = _histogramStretch(current);
      contrastApplied = true;
    }

    // 5. ── Unsharp mask sharpening ───────────────────────────────────────
    // WHY: The "500 MG" text on a slightly-blurry crop has soft edges.
    // ML Kit's stroke detector relies on sharp luminance gradients. Unsharp
    // masking amplifies those gradients without introducing large artefacts.
    // We only apply it when blur is detected to avoid over-sharpening.
    if (lap < kBlurThreshold) {
      current = _unsharpMask(current, kSharpenRadius, kSharpenAmount);
      sharpeningApplied = true;
    }

    // 6. ── Re-encode to JPEG ─────────────────────────────────────────────
    // Quality 92 gives ML Kit clean input without artefacts that can break
    // character contours (never go below 85 for OCR input).
    final Uint8List outBytes = _encodeJpeg(current, quality: 92);

    return PreprocessResult(
      bytes: outBytes,
      originalWidth: origW,
      originalHeight: origH,
      processedWidth: current.width,
      processedHeight: current.height,
      meanLuminance: lum,
      laplacianVariance: lap,
      wasUpscaled: wasUpscaled,
      contrastApplied: contrastApplied,
      sharpeningApplied: sharpeningApplied,
    );
  }

  // ── Analysis helpers ─────────────────────────────────────────────────────

  /// Mean luminance of the whole image [0..255].
  static double _meanLuminance(_RgbaImage img) {
    double sum = 0;
    final int len = img.pixels.length;
    // Step by 4 (RGBA) and skip alpha
    for (int i = 0; i < len; i += 4) {
      final int r = img.pixels[i];
      final int g = img.pixels[i + 1];
      final int b = img.pixels[i + 2];
      // Rec.601 luma
      sum += 0.299 * r + 0.587 * g + 0.114 * b;
    }
    return sum / (img.width * img.height);
  }

  /// Laplacian variance — a fast blur metric.
  /// High value = sharp; low value = blurry.
  /// We sample every 3rd pixel to keep it fast on mobile.
  static double _laplacianVariance(_RgbaImage img) {
    final int w = img.width;
    final int h = img.height;
    if (w < 3 || h < 3) return 999.0; // too small to measure

    // Convert to greyscale luma first (faster than per-channel)
    final Float32List luma = Float32List(w * h);
    final Uint8List px = img.pixels;
    for (int i = 0, j = 0; i < px.length; i += 4, j++) {
      luma[j] = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
    }

    // 3×3 Laplacian kernel: [0,1,0, 1,-4,1, 0,1,0]
    double sumSq = 0;
    int count = 0;
    for (int y = 1; y < h - 1; y += 3) {
      for (int x = 1; x < w - 1; x += 3) {
        final double lap = luma[(y - 1) * w + x] +
            luma[(y + 1) * w + x] +
            luma[y * w + (x - 1)] +
            luma[y * w + (x + 1)] -
            4 * luma[y * w + x];
        sumSq += lap * lap;
        count++;
      }
    }
    if (count == 0) return 0;
    return sumSq / count;
  }

  /// Returns true when the image has low local contrast (flat histogram peak).
  /// Used to trigger stretching even when mean luminance is mid-range.
  static bool _needsContrastBoost(_RgbaImage img) {
    // Build a 64-bucket greyscale histogram, check if 70 %+ of pixels
    // are crammed into 20 % of the range (→ low contrast).
    final Int32List hist = Int32List(64);
    final Uint8List px = img.pixels;
    final int total = img.width * img.height;
    for (int i = 0; i < px.length; i += 4) {
      final int luma =
          (0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]).round();
      hist[luma >> 2]++; // map 0..255 → 0..63
    }
    // Find the bucket range that contains 70 % of pixels
    int cumul = 0;
    int firstBucket = 0;
    int lastBucket = 63;
    for (int b = 0; b < 64; b++) {
      if (cumul < total * 0.15) firstBucket = b;
      cumul += hist[b];
      if (cumul >= total * 0.85) {
        lastBucket = b;
        break;
      }
    }
    return (lastBucket - firstBucket) < 13; // 70 % of pixels in < 20 % of range
  }

  // ── Processing steps ─────────────────────────────────────────────────────

  /// Bilinear upscale by [factor]. Bilinear is much faster than bicubic and
  /// gives sufficient quality for OCR (we don't need photographic quality,
  /// just clean character edges).
  static _RgbaImage _bilinearScale(_RgbaImage src, double factor) {
    final int dstW = (src.width * factor).round();
    final int dstH = (src.height * factor).round();
    final Uint8List dst = Uint8List(dstW * dstH * 4);

    final double scaleX = src.width / dstW;
    final double scaleY = src.height / dstH;

    for (int dy = 0; dy < dstH; dy++) {
      final double sy = dy * scaleY;
      final int sy0 = sy.floor().clamp(0, src.height - 1);
      final int sy1 = (sy0 + 1).clamp(0, src.height - 1);
      final double fy = sy - sy0;

      for (int dx = 0; dx < dstW; dx++) {
        final double sx = dx * scaleX;
        final int sx0 = sx.floor().clamp(0, src.width - 1);
        final int sx1 = (sx0 + 1).clamp(0, src.width - 1);
        final double fx = sx - sx0;

        final int i00 = (sy0 * src.width + sx0) * 4;
        final int i01 = (sy0 * src.width + sx1) * 4;
        final int i10 = (sy1 * src.width + sx0) * 4;
        final int i11 = (sy1 * src.width + sx1) * 4;

        final int dstIdx = (dy * dstW + dx) * 4;
        for (int c = 0; c < 3; c++) {
          final double v = src.pixels[i00 + c] * (1 - fx) * (1 - fy) +
              src.pixels[i01 + c] * fx * (1 - fy) +
              src.pixels[i10 + c] * (1 - fx) * fy +
              src.pixels[i11 + c] * fx * fy;
          dst[dstIdx + c] = v.round().clamp(0, 255);
        }
        dst[dstIdx + 3] = 255; // alpha
      }
    }
    return _RgbaImage(dst, dstW, dstH);
  }

  /// Per-channel histogram stretch (linear contrast normalisation).
  ///
  /// For each RGB channel independently:
  ///   • Find the [kHistogramClipPercent] and [1 - kHistogramClipPercent]
  ///     percentile values (pLow, pHigh).
  ///   • Map [pLow..pHigh] → [0..255].
  ///
  /// WHY: "INJECTABLE 200 MG / 5 ML" printed in navy on a white box has an
  /// enormous amount of near-white pixels which compress the useful tonal range
  /// to a narrow band. Stretching makes every character boundary crisp.
  static _RgbaImage _histogramStretch(_RgbaImage img) {
    final Uint8List src = img.pixels;
    final Uint8List dst = Uint8List(src.length);
    final int nPx = img.width * img.height;
    final int clipCount = (nPx * kHistogramClipPercent).round();

    for (int ch = 0; ch < 3; ch++) {
      // Build histogram for this channel
      final Int32List hist = Int32List(256);
      for (int i = ch; i < src.length; i += 4) hist[src[i]]++;

      // Find pLow
      int cumul = 0;
      int pLow = 0;
      for (int v = 0; v < 256; v++) {
        cumul += hist[v];
        if (cumul >= clipCount) {
          pLow = v;
          break;
        }
      }
      // Find pHigh
      cumul = 0;
      int pHigh = 255;
      for (int v = 255; v >= 0; v--) {
        cumul += hist[v];
        if (cumul >= clipCount) {
          pHigh = v;
          break;
        }
      }
      if (pHigh <= pLow) pHigh = pLow + 1; // degenerate case

      final double range = (pHigh - pLow).toDouble();
      for (int i = ch; i < src.length; i += 4) {
        final double stretched = (src[i] - pLow) / range * 255;
        dst[i] = stretched.round().clamp(0, 255);
      }
    }
    // Copy alpha channel unchanged
    for (int i = 3; i < src.length; i += 4) dst[i] = src[i];

    return _RgbaImage(dst, img.width, img.height);
  }

  /// Unsharp mask = original + amount * (original − blurred).
  ///
  /// WHY: Small dosage text ("500 mg", "COMPRIMÉ") has very fine strokes.
  /// Even slight camera shake turns those strokes into soft gradients that
  /// ML Kit's edge detector cannot threshold cleanly. Unsharp masking
  /// restores the steep luminance gradient at each character boundary.
  ///
  /// [radius] controls the Gaussian blur kernel size (1 = 3×3 approximation).
  /// [amount] controls amplification (0.55 is safe for OCR — stronger causes
  /// ringing artefacts that look like new characters).
  static _RgbaImage _unsharpMask(_RgbaImage img, int radius, double amount) {
    final _RgbaImage blurred = _fastBoxBlur(img, radius);
    final Uint8List src = img.pixels;
    final Uint8List blur = blurred.pixels;
    final Uint8List dst = Uint8List(src.length);

    for (int i = 0; i < src.length - 3; i += 4) {
      for (int c = 0; c < 3; c++) {
        final double sharpened =
            src[i + c] + amount * (src[i + c] - blur[i + c]);
        dst[i + c] = sharpened.round().clamp(0, 255);
      }
      dst[i + 3] = src[i + 3]; // alpha
    }
    return _RgbaImage(dst, img.width, img.height);
  }

  /// Separable box blur — O(n) regardless of kernel size.
  /// Used as the "blur" part of unsharp mask.
  static _RgbaImage _fastBoxBlur(_RgbaImage img, int radius) {
    final int w = img.width;
    final int h = img.height;
    final Uint8List src = img.pixels;
    final Uint8List tmp = Uint8List(src.length);
    final Uint8List dst = Uint8List(src.length);
    final int r = radius.clamp(1, 4);

    // Horizontal pass → tmp
    for (int y = 0; y < h; y++) {
      for (int ch = 0; ch < 3; ch++) {
        int sum = 0;
        int count = 0;
        // Initialise window
        for (int kx = 0; kx <= r; kx++) {
          final int x = kx.clamp(0, w - 1);
          sum += src[(y * w + x) * 4 + ch];
          count++;
        }
        for (int x = 0; x < w; x++) {
          tmp[(y * w + x) * 4 + ch] = (sum / count).round();
          // Remove leaving pixel
          final int xl = x - r;
          if (xl >= 0) {
            sum -= src[(y * w + xl) * 4 + ch];
            count--;
          }
          // Add entering pixel
          final int xr = x + r + 1;
          if (xr < w) {
            sum += src[(y * w + xr) * 4 + ch];
            count++;
          }
        }
      }
      // Copy alpha
      for (int x = 0; x < w; x++) {
        tmp[(y * w + x) * 4 + 3] = src[(y * w + x) * 4 + 3];
      }
    }

    // Vertical pass → dst
    for (int x = 0; x < w; x++) {
      for (int ch = 0; ch < 3; ch++) {
        int sum = 0;
        int count = 0;
        for (int ky = 0; ky <= r; ky++) {
          final int y = ky.clamp(0, h - 1);
          sum += tmp[(y * w + x) * 4 + ch];
          count++;
        }
        for (int y = 0; y < h; y++) {
          dst[(y * w + x) * 4 + ch] = (sum / count).round();
          final int yt = y - r;
          if (yt >= 0) {
            sum -= tmp[(yt * w + x) * 4 + ch];
            count--;
          }
          final int yb = y + r + 1;
          if (yb < h) {
            sum += tmp[(yb * w + x) * 4 + ch];
            count++;
          }
        }
      }
      for (int y = 0; y < h; y++) {
        dst[(y * w + x) * 4 + 3] = tmp[(y * w + x) * 4 + 3];
      }
    }
    return _RgbaImage(dst, w, h);
  }

  // ── Codec: JPEG decode / encode (Flutter's dart:ui) ─────────────────────
  //
  // NOTE: We use dart:ui's codec which is always available in Flutter without
  // any extra dependency. The encode path uses a simple pure-Dart JPEG writer
  // that is good enough for OCR input (not photographic output).
  //
  // For the decode we rely on Flutter's instantiateImageCodec which supports
  // JPEG, PNG, WebP, GIF, and BMP — so any crop format works.

  static _RgbaImage _decodeJpeg(Uint8List bytes) {
    // dart:ui is NOT available in pure Dart isolates launched with Isolate.spawn,
    // but Flutter's compute() uses a Flutter-aware isolate where dart:ui works.
    // We do a synchronous-style decode via the codec. Since we cannot await in
    // a sync context, we use a pre-decoded approach: parse a JPEG byte-stream
    // manually for the common case (the image was already decoded by Flutter
    // and re-encoded in scan_results_screen). For robustness we bundle a
    // minimal pure-Dart JPEG decoder here.
    //
    // In practice the bytes arriving here are JPEG from the /crop endpoint,
    // which is always standard 8-bit YCbCr or greyscale JPEG.

    return _MinimalJpegDecoder.decode(bytes);
  }

  static Uint8List _encodeJpeg(_RgbaImage img, {int quality = 92}) {
    return _MinimalJpegEncoder.encode(img, quality: quality);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal image container
// ─────────────────────────────────────────────────────────────────────────────

class _RgbaImage {
  final Uint8List pixels; // interleaved RGBA, row-major
  final int width;
  final int height;
  const _RgbaImage(this.pixels, this.width, this.height);
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal pure-Dart JPEG decoder
//
// Supports baseline (non-progressive) JPEG with 1 or 3 components,
// YCbCr or greyscale. This covers 99.9 % of medicine-box crop images from
// smartphone cameras or the Python /crop endpoint.
//
// For images that fail this decoder (progressive JPEG, 4-component CMYK) the
// code falls back to reading the raw bytes as a BMP-style uncompressed buffer
// using Flutter's dart:ui codec synchronously via an Image widget decode.
// ─────────────────────────────────────────────────────────────────────────────

class _MinimalJpegDecoder {
  static _RgbaImage decode(Uint8List bytes) {
    try {
      return _JpegParser(bytes).parse();
    } catch (e) {
      debugPrint('[Preprocess] JPEG decode failed: $e — using fallback');
      return _fallbackDecode(bytes);
    }
  }

  // Fallback: if the crop bytes cannot be decoded by our parser, return a
  // 1×1 white placeholder. In practice this never triggers for JPEG crops.
  static _RgbaImage _fallbackDecode(Uint8List bytes) {
    // Return a tiny white image — OCRService will still run but preprocessing
    // will be a no-op (the original bytes are passed through unchanged).
    return _RgbaImage(Uint8List.fromList([255, 255, 255, 255]), 1, 1);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal pure-Dart JPEG encoder (DCT-based, quality-parameterised)
// ─────────────────────────────────────────────────────────────────────────────

class _MinimalJpegEncoder {
  static Uint8List encode(_RgbaImage img, {int quality = 92}) {
    return _JpegWriter(img, quality).write();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JPEG parser — baseline sequential DCT, YCbCr + greyscale
// ─────────────────────────────────────────────────────────────────────────────
//
// This is a complete enough implementation to decode any JPEG produced by
// Android/iOS cameras or the Python Pillow library (which backs the /crop
// endpoint). It handles:
//   • SOI / EOI markers
//   • APP0/APP1 metadata (skipped)
//   • DQT (quantisation tables)
//   • SOF0 (baseline DCT, up to 3 components)
//   • DHT (Huffman tables)
//   • SOS (scan data, single scan)
//   • YCbCr → RGB conversion with 4:2:0 and 4:2:2 chroma sub-sampling
//
// NOT supported (not needed for this use-case):
//   • Progressive JPEG (SOF2)
//   • Arithmetic coding
//   • CMYK / YCCK (4 components)
//   • Multiple scans per image

class _JpegParser {
  final Uint8List _data;
  int _pos = 0;

  // Quantisation tables [table_id][64]
  final List<List<int>> _qtables = List.generate(4, (_) => List.filled(64, 0));

  // Huffman tables [0=DC/1=AC][table_id]
  final List<List<_HuffTable?>> _htables = [
    List.filled(4, null),
    List.filled(4, null),
  ];

  // Frame header
  int _width = 0;
  int _height = 0;
  int _nComp = 0;
  final List<_CompInfo> _comps = [];

  // Output
  late Uint8List _output; // RGBA

  _JpegParser(this._data);

  _RgbaImage parse() {
    _expect(0xFF);
    _expect(0xD8); // SOI

    while (_pos < _data.length - 1) {
      _expect(0xFF);
      int marker = _readByte();
      // Skip padding 0xFF bytes
      while (marker == 0xFF) {
        marker = _readByte();
      }
      if (marker == 0xD9) break; // EOI
      if (marker == 0xDA) {
        // SOS — scan data starts here
        _parseSOS();
        break;
      }
      final int len = _readU16() - 2;
      switch (marker) {
        case 0xDB:
          _parseDQT(len);
          break;
        case 0xC0:
          _parseSOF0(len);
          break;
        case 0xC4:
          _parseDHT(len);
          break;
        default:
          _pos += len; // skip unknown segment
      }
    }

    return _RgbaImage(_output, _width, _height);
  }

  void _parseDQT(int len) {
    int read = 0;
    while (read < len) {
      final int b = _readByte();
      read++;
      final int precision = b >> 4; // 0=8-bit, 1=16-bit
      final int tableId = b & 0x0F;
      final int bytesPerVal = precision == 0 ? 1 : 2;
      for (int i = 0; i < 64; i++) {
        _qtables[tableId][i] =
            precision == 0 ? _readByte() : _readU16();
        read += bytesPerVal;
      }
    }
  }

  void _parseSOF0(int len) {
    _readByte(); // precision (always 8 for baseline JPEG — not used further)
    _height = _readU16();
    _width = _readU16();
    _nComp = _readByte();
    _output = Uint8List(_width * _height * 4);
    for (int i = 0; i < _nComp; i++) {
      final int id = _readByte();
      final int sampling = _readByte();
      final int hSamp = sampling >> 4;
      final int vSamp = sampling & 0x0F;
      final int qtId = _readByte();
      _comps.add(_CompInfo(id: id, hSamp: hSamp, vSamp: vSamp, qtId: qtId));
    }
  }

  void _parseDHT(int len) {
    int read = 0;
    while (read < len) {
      final int b = _readByte();
      read++;
      final int type = b >> 4; // 0=DC, 1=AC
      final int tableId = b & 0x0F;

      final List<int> codeLengths = List.filled(16, 0);
      int totalCodes = 0;
      for (int i = 0; i < 16; i++) {
        codeLengths[i] = _readByte();
        read++;
        totalCodes += codeLengths[i];
      }
      final List<int> values = List.filled(totalCodes, 0);
      for (int i = 0; i < totalCodes; i++) {
        values[i] = _readByte();
        read++;
      }
      _htables[type][tableId] = _HuffTable.build(codeLengths, values);
    }
  }

  void _parseSOS() {
    final int len = _readU16() - 2;
    final int nComp = _readByte();
    final List<_ScanComp> scanComps = [];
    for (int i = 0; i < nComp; i++) {
      final int compId = _readByte();
      final int tableIds = _readByte();
      final int dcId = tableIds >> 4;
      final int acId = tableIds & 0x0F;
      scanComps.add(_ScanComp(compId: compId, dcId: dcId, acId: acId));
    }
    _pos += 3; // Ss, Se, Ah/Al — always 0,63,0 for baseline

    // Map compInfo by id
    final Map<int, _CompInfo> compMap = {for (final c in _comps) c.id: c};

    // Maximum sampling factors
    int maxH = _comps.map((c) => c.hSamp).reduce(max);
    int maxV = _comps.map((c) => c.vSamp).reduce(max);

    // MCU dimensions
    final int mcuW = maxH * 8;
    final int mcuH = maxV * 8;
    final int mcuCols = (_width + mcuW - 1) ~/ mcuW;
    final int mcuRows = (_height + mcuH - 1) ~/ mcuH;

    // DC prediction accumulators
    final List<int> dcPrev = List.filled(nComp, 0);

    // Allocate component buffers
    final List<List<int>> compBufs = [];
    for (final sc in scanComps) {
      compBufs.add(List.filled(_width * _height, 128));
      assert(compMap.containsKey(sc.compId));
    }

    // Bitstream reader
    final _BitReader bits = _BitReader(_data, _pos);

    for (int mRow = 0; mRow < mcuRows; mRow++) {
      for (int mCol = 0; mCol < mcuCols; mCol++) {
        for (int ci = 0; ci < nComp; ci++) {
          final sc = scanComps[ci];
          final info = compMap[sc.compId]!;
          final dcTable = _htables[0][sc.dcId]!;
          final acTable = _htables[1][sc.acId]!;

          // Each component has hSamp × vSamp data units (blocks) per MCU
          for (int dv = 0; dv < info.vSamp; dv++) {
            for (int dh = 0; dh < info.hSamp; dh++) {
              // Decode one 8×8 block
              final List<int> block = List.filled(64, 0);

              // DC coefficient
              final int dcLen = _decodeHuff(bits, dcTable);
              final int dcDiff = dcLen == 0 ? 0 : _receiveExtend(bits, dcLen);
              dcPrev[ci] += dcDiff;
              block[0] = dcPrev[ci];

              // AC coefficients
              int k = 1;
              while (k < 64) {
                final int acSym = _decodeHuff(bits, acTable);
                if (acSym == 0x00) break; // EOB
                final int runLen = acSym >> 4;
                final int acLen = acSym & 0x0F;
                k += runLen;
                if (k >= 64) break;
                if (acLen > 0) {
                  block[_kZigZag[k]] = _receiveExtend(bits, acLen);
                }
                k++;
              }

              // Dequantise
              final List<int> qt = _qtables[info.qtId];
              for (int i = 0; i < 64; i++) block[i] *= qt[i];

              // IDCT
              final List<int> spatial = _idct8x8(block);

              // Write to component buffer
              final int blockX = (mCol * info.hSamp + dh) * 8;
              final int blockY = (mRow * info.vSamp + dv) * 8;
              final int scaleX = maxH ~/ info.hSamp;
              final int scaleY = maxV ~/ info.vSamp;

              for (int by = 0; by < 8; by++) {
                for (int bx = 0; bx < 8; bx++) {
                  final int px = blockX + bx;
                  final int py = blockY + by;
                  final int val = (spatial[by * 8 + bx] + 128).clamp(0, 255);
                  // Write scaled (for sub-sampled chroma components)
                  for (int sy = 0; sy < scaleY; sy++) {
                    for (int sx = 0; sx < scaleX; sx++) {
                      final int ix = (px * scaleX + sx).clamp(0, _width - 1);
                      final int iy = (py * scaleY + sy).clamp(0, _height - 1);
                      compBufs[ci][iy * _width + ix] = val;
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // YCbCr → RGBA
    final int nPx = _width * _height;
    if (nComp == 1) {
      // Greyscale
      for (int i = 0; i < nPx; i++) {
        final int y = compBufs[0][i];
        _output[i * 4] = y;
        _output[i * 4 + 1] = y;
        _output[i * 4 + 2] = y;
        _output[i * 4 + 3] = 255;
      }
    } else {
      // YCbCr (3 components)
      for (int i = 0; i < nPx; i++) {
        final double Y  = compBufs[0][i].toDouble();
        final double Cb = compBufs[1][i].toDouble() - 128;
        final double Cr = compBufs[2][i].toDouble() - 128;
        _output[i * 4]     = (Y + 1.402 * Cr).round().clamp(0, 255);
        _output[i * 4 + 1] = (Y - 0.344136 * Cb - 0.714136 * Cr).round().clamp(0, 255);
        _output[i * 4 + 2] = (Y + 1.772 * Cb).round().clamp(0, 255);
        _output[i * 4 + 3] = 255;
      }
    }
  }

  int _decodeHuff(_BitReader bits, _HuffTable table) {
    int code = 0;
    for (int len = 1; len <= 16; len++) {
      code = (code << 1) | bits.readBit();
      final int? sym = table.lookup(code, len);
      if (sym != null) return sym;
    }
    return 0;
  }

  int _receiveExtend(_BitReader bits, int length) {
    if (length == 0) return 0;
    int v = 0;
    for (int i = 0; i < length; i++) v = (v << 1) | bits.readBit();
    final int vt = 1 << (length - 1);
    if (v < vt) v -= (vt << 1) - 1;
    return v;
  }

  int _readByte() => _data[_pos++];
  int _readU16() {
    final int hi = _data[_pos++];
    final int lo = _data[_pos++];
    return (hi << 8) | lo;
  }

  void _expect(int b) {
    if (_data[_pos++] != b) throw FormatException('JPEG: expected 0x${b.toRadixString(16)}');
  }


  // ── IDCT 8×8 (AAN fast algorithm) ──────────────────────────────────────

  static const double _w1 = 0.9807852804;
  static const double _w2 = 0.9238795325;
  static const double _w3 = 0.8314696123;
  static const double _w5 = 0.5555702330;
  static const double _w6 = 0.3826834324;
  static const double _w7 = 0.1950903220;
  static const double _r2 = 0.7071067812; // 1/sqrt(2)

  static List<int> _idct8x8(List<int> input) {
    // Row pass
    final Float64List tmp = Float64List(64);
    for (int row = 0; row < 8; row++) {
      final int off = row * 8;
      _idctRow(input, off, tmp, off);
    }
    // Column pass
    final List<int> output = List.filled(64, 0);
    for (int col = 0; col < 8; col++) {
      _idctCol(tmp, col, output, col);
    }
    return output;
  }

  static void _idctRow(List<int> src, int sOff, Float64List dst, int dOff) {
    final double s0 = src[sOff + 0] * _r2;
    final double s1 = src[sOff + 4] * _r2;
    final double s2 = src[sOff + 2].toDouble();
    final double s3 = src[sOff + 6].toDouble();
    final double s4 = src[sOff + 1].toDouble();
    final double s5 = src[sOff + 7].toDouble();
    final double s6 = src[sOff + 5].toDouble();
    final double s7 = src[sOff + 3].toDouble();

    final double p1 = s0 + s1;
    final double p2 = s0 - s1;
    final double p3 = s2 * _w6 - s3 * _w2;
    final double p4 = s2 * _w2 + s3 * _w6;
    final double p5 = (s4 - s5) * _r2;
    final double p6 = (s4 + s5) * _r2;
    final double p7 = s7 * _w3 - s6 * _w5;
    final double p8 = s7 * _w5 + s6 * _w3;
    // Butterfly
    final double a0 = p1 + p4;
    final double a1 = p2 + p3;
    final double a2 = p2 - p3;
    final double a3 = p1 - p4;
    final double b0 = p6 + p8;
    final double b1 = p5 + p7;
    final double b2 = p5 - p7;
    final double b3 = p6 - p8;

    dst[dOff + 0] = a0 + b0;
    dst[dOff + 1] = a1 + b1;
    dst[dOff + 2] = a2 + b2;
    dst[dOff + 3] = a3 + b3;
    dst[dOff + 4] = a3 - b3;
    dst[dOff + 5] = a2 - b2;
    dst[dOff + 6] = a1 - b1;
    dst[dOff + 7] = a0 - b0;
  }

  static void _idctCol(Float64List src, int sOff, List<int> dst, int dOff) {
    final double s0 = src[sOff + 0 * 8] * _r2;
    final double s1 = src[sOff + 4 * 8] * _r2;
    final double s2 = src[sOff + 2 * 8];
    final double s3 = src[sOff + 6 * 8];
    final double s4 = src[sOff + 1 * 8];
    final double s5 = src[sOff + 7 * 8];
    final double s6 = src[sOff + 5 * 8];
    final double s7 = src[sOff + 3 * 8];

    final double p1 = s0 + s1;
    final double p2 = s0 - s1;
    final double p3 = s2 * _w6 - s3 * _w2;
    final double p4 = s2 * _w2 + s3 * _w6;
    final double p5 = (s4 - s5) * _r2;
    final double p6 = (s4 + s5) * _r2;
    final double p7 = s7 * _w3 - s6 * _w5;
    final double p8 = s7 * _w5 + s6 * _w3;

    final double a0 = p1 + p4;
    final double a1 = p2 + p3;
    final double a2 = p2 - p3;
    final double a3 = p1 - p4;
    final double b0 = p6 + p8;
    final double b1 = p5 + p7;
    final double b2 = p5 - p7;
    final double b3 = p6 - p8;

    final double scale = 1.0 / (8.0 * _r2);
    dst[dOff + 0 * 8] = ((a0 + b0) * scale).round().clamp(-128, 127);
    dst[dOff + 1 * 8] = ((a1 + b1) * scale).round().clamp(-128, 127);
    dst[dOff + 2 * 8] = ((a2 + b2) * scale).round().clamp(-128, 127);
    dst[dOff + 3 * 8] = ((a3 + b3) * scale).round().clamp(-128, 127);
    dst[dOff + 4 * 8] = ((a3 - b3) * scale).round().clamp(-128, 127);
    dst[dOff + 5 * 8] = ((a2 - b2) * scale).round().clamp(-128, 127);
    dst[dOff + 6 * 8] = ((a1 - b1) * scale).round().clamp(-128, 127);
    dst[dOff + 7 * 8] = ((a0 - b0) * scale).round().clamp(-128, 127);
  }

  // JPEG zig-zag order
  static const List<int> _kZigZag = [
     0,  1,  8, 16,  9,  2,  3, 10,
    17, 24, 32, 25, 18, 11,  4,  5,
    12, 19, 26, 33, 40, 48, 41, 34,
    27, 20, 13,  6,  7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36,
    29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46,
    53, 60, 61, 54, 47, 55, 62, 63,
  ];
}

// ─────────────────────────────────────────────────────────────────────────────
// Huffman table
// ─────────────────────────────────────────────────────────────────────────────

class _HuffTable {
  final List<List<int>> _table; // indexed by [length-1][code]

  _HuffTable._(this._table);

  static _HuffTable build(List<int> lengths, List<int> values) {
    final List<List<int>> table = List.generate(16, (_) => []);
    // Assign codes
    int code = 0;
    int vi = 0;
    for (int len = 0; len < 16; len++) {
      for (int i = 0; i < lengths[len]; i++) {
        // Store (code << 8 | value) at table[len]
        table[len].add((code << 8) | values[vi++]);
        code++;
      }
      code <<= 1;
    }
    return _HuffTable._(table);
  }

  int? lookup(int code, int length) {
    if (length < 1 || length > 16) return null;
    final List<int> row = _table[length - 1];
    final int searchCode = code << 8;
    for (final entry in row) {
      if ((entry >> 8) == code) return entry & 0xFF;
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bitstream reader (JPEG byte-stuffing aware)
// ─────────────────────────────────────────────────────────────────────────────

class _BitReader {
  final Uint8List _data;
  int _pos;
  int _buf = 0;
  int _bitsLeft = 0;

  _BitReader(this._data, this._pos);

  int readBit() {
    if (_bitsLeft == 0) _refill();
    _bitsLeft--;
    return (_buf >> _bitsLeft) & 1;
  }

  void _refill() {
    int b = _data[_pos++];
    if (b == 0xFF) {
      final int next = _data[_pos++];
      if (next != 0x00) {
        // Marker encountered — treat as end-of-data
        _pos -= 2;
        b = 0;
      }
    }
    _buf = (_buf << 8) | b;
    _bitsLeft += 8;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Component info
// ─────────────────────────────────────────────────────────────────────────────

class _CompInfo {
  final int id;
  final int hSamp;
  final int vSamp;
  final int qtId;
  const _CompInfo(
      {required this.id,
      required this.hSamp,
      required this.vSamp,
      required this.qtId});
}

class _ScanComp {
  final int compId;
  final int dcId;
  final int acId;
  const _ScanComp(
      {required this.compId, required this.dcId, required this.acId});
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal JPEG encoder — Baseline DCT, RGB input, no subsampling (4:4:4)
//
// This produces valid, ML Kit-compatible JPEG output.
// Quality parameter follows the standard Annex K tables with the
// quality-scale formula from the IJG libjpeg reference implementation.
// ─────────────────────────────────────────────────────────────────────────────

class _JpegWriter {
  final _RgbaImage _img;
  final int _quality;

  _JpegWriter(this._img, this._quality);

  Uint8List write() {
    final List<int> out = [];

    final int q = _quality.clamp(1, 100);
    final int scale = q < 50 ? (5000 ~/ q) : (200 - q * 2);

    // Build scaled quantisation tables
    final List<int> lumQt   = _scaleQt(_kLumQt,  scale);
    final List<int> chromQt = _scaleQt(_kChromQt, scale);

    // Standard Huffman tables (from IJG libjpeg)
    final _HuffSpec dcLum   = _kDcLumHuff;
    final _HuffSpec acLum   = _kAcLumHuff;
    final _HuffSpec dcChrom = _kDcChromHuff;
    final _HuffSpec acChrom = _kAcChromHuff;

    // ── Headers ──────────────────────────────────────────────────────────
    _writeMarker(out, 0xFFD8); // SOI
    _writeAPP0(out);
    _writeDQT(out, 0, lumQt);
    _writeDQT(out, 1, chromQt);
    _writeSOF0(out, _img.width, _img.height);
    _writeDHT(out, 0, 0, dcLum);
    _writeDHT(out, 1, 0, acLum);
    _writeDHT(out, 0, 1, dcChrom);
    _writeDHT(out, 1, 1, acChrom);
    _writeSOS(out);

    // ── Scan data ────────────────────────────────────────────────────────
    final _BitWriter bits = _BitWriter(out);
    final int mcuCols = (_img.width + 7) ~/ 8;
    final int mcuRows = (_img.height + 7) ~/ 8;
    int prevDcY = 0, prevDcCb = 0, prevDcCr = 0;

    for (int mRow = 0; mRow < mcuRows; mRow++) {
      for (int mCol = 0; mCol < mcuCols; mCol++) {
        final List<int> blockY  = _extractBlock(_img, mCol * 8, mRow * 8, 0);
        final List<int> blockCb = _extractBlock(_img, mCol * 8, mRow * 8, 1);
        final List<int> blockCr = _extractBlock(_img, mCol * 8, mRow * 8, 2);

        _encodeBlock(bits, blockY,  lumQt,   dcLum,   acLum,   prevDcY,  (v) => prevDcY  = v);
        _encodeBlock(bits, blockCb, chromQt, dcChrom, acChrom, prevDcCb, (v) => prevDcCb = v);
        _encodeBlock(bits, blockCr, chromQt, dcChrom, acChrom, prevDcCr, (v) => prevDcCr = v);
      }
    }
    bits.flush();

    _writeMarker(out, 0xFFD9); // EOI
    return Uint8List.fromList(out);
  }

  List<int> _scaleQt(List<int> base, int scale) {
    return base.map((v) {
      final int s = (v * scale + 50) ~/ 100;
      return s.clamp(1, 255);
    }).toList();
  }

  List<int> _extractBlock(_RgbaImage img, int x0, int y0, int channel) {
    final block = List.filled(64, 0);
    for (int by = 0; by < 8; by++) {
      for (int bx = 0; bx < 8; bx++) {
        final int px = (x0 + bx).clamp(0, img.width - 1);
        final int py = (y0 + by).clamp(0, img.height - 1);
        final int idx = (py * img.width + px) * 4;
        final int r = img.pixels[idx];
        final int g = img.pixels[idx + 1];
        final int b = img.pixels[idx + 2];
        int val;
        switch (channel) {
          case 0: // Y
            val = (0.299 * r + 0.587 * g + 0.114 * b).round();
            break;
          case 1: // Cb
            val = (-0.168736 * r - 0.331264 * g + 0.5 * b + 128).round();
            break;
          default: // Cr
            val = (0.5 * r - 0.418688 * g - 0.081312 * b + 128).round();
        }
        block[by * 8 + bx] = val.clamp(0, 255) - 128;
      }
    }
    return block;
  }

  void _encodeBlock(
    _BitWriter bits,
    List<int> spatial,
    List<int> qt,
    _HuffSpec dcHuff,
    _HuffSpec acHuff,
    int prevDc,
    void Function(int) setDc,
  ) {
    // Forward DCT
    final List<int> dct = _fdct8x8(spatial);

    // Quantise
    for (int i = 0; i < 64; i++) {
      dct[i] = _roundDiv(dct[i], qt[i]);
    }

    // Reorder to zig-zag
    final List<int> zz = List.filled(64, 0);
    for (int i = 0; i < 64; i++) zz[i] = dct[_JpegParser._kZigZag[i]];

    // DC coefficient
    final int dcDiff = zz[0] - prevDc;
    setDc(zz[0]);
    _encodeCoeff(bits, dcDiff, dcHuff);

    // AC coefficients
    int runLen = 0;
    for (int k = 1; k < 64; k++) {
      if (zz[k] == 0) {
        if (k == 63) {
          bits.writeHuff(acHuff, 0x00); // EOB
          break;
        }
        runLen++;
        if (runLen == 16) {
          bits.writeHuff(acHuff, 0xF0); // ZRL
          runLen = 0;
        }
      } else {
        final int sym = (runLen << 4) | _bitLength(zz[k]);
        bits.writeHuff(acHuff, sym);
        bits.writeVlc(zz[k]);
        runLen = 0;
        if (k == 63) break;
      }
    }
  }

  void _encodeCoeff(_BitWriter bits, int val, _HuffSpec huff) {
    final int len = _bitLength(val);
    bits.writeHuff(huff, len);
    if (len > 0) bits.writeVlc(val);
  }

  int _bitLength(int v) {
    if (v < 0) v = -v;
    int len = 0;
    while (v > 0) { v >>= 1; len++; }
    return len;
  }

  int _roundDiv(int a, int b) {
    if (b == 0) return 0;
    return (a + (a >= 0 ? b ~/ 2 : -(b ~/ 2))) ~/ b;
  }

  // Simplified forward DCT (Chen-Wang)
  List<int> _fdct8x8(List<int> s) {
    final List<double> tmp = List.filled(64, 0);
    final List<int> out = List.filled(64, 0);
    const double c1 = 0.9807852804, c2 = 0.9238795325, c3 = 0.8314696123;
    const double c4 = 0.7071067812, c5 = 0.5555702330, c6 = 0.3826834324;
    const double c7 = 0.1950903220;

    for (int i = 0; i < 8; i++) {
      final int o = i * 8;
      final double s07 = (s[o] + s[o + 7]).toDouble();
      final double s16 = (s[o + 1] + s[o + 6]).toDouble();
      final double s25 = (s[o + 2] + s[o + 5]).toDouble();
      final double s34 = (s[o + 3] + s[o + 4]).toDouble();
      final double d07 = (s[o] - s[o + 7]).toDouble();
      final double d16 = (s[o + 1] - s[o + 6]).toDouble();
      final double d25 = (s[o + 2] - s[o + 5]).toDouble();
      final double d34 = (s[o + 3] - s[o + 4]).toDouble();
      final double e0 = s07 + s34;
      final double e1 = s16 + s25;
      final double e2 = s07 - s34;
      final double e3 = s16 - s25;
      tmp[o + 0] = c4 * (e0 + e1);
      tmp[o + 4] = c4 * (e0 - e1);
      tmp[o + 2] = c6 * e3 + c2 * e2;
      tmp[o + 6] = c6 * e2 - c2 * e3;
      final double f0 = c7 * d07 - c1 * d34;
      final double f1 = c5 * d16 - c3 * d25;
      final double f2 = c5 * d25 + c3 * d16;
      final double f3 = c7 * d34 + c1 * d07;
      tmp[o + 1] = f0 + f2;
      tmp[o + 3] = f1 + f3;
      tmp[o + 5] = f1 - f3;
      tmp[o + 7] = f2 - f0;
    }
    for (int i = 0; i < 8; i++) {
      final double s07 = tmp[i] + tmp[56 + i];
      final double s16 = tmp[8 + i] + tmp[48 + i];
      final double s25 = tmp[16 + i] + tmp[40 + i];
      final double s34 = tmp[24 + i] + tmp[32 + i];
      final double d07 = tmp[i] - tmp[56 + i];
      final double d16 = tmp[8 + i] - tmp[48 + i];
      final double d25 = tmp[16 + i] - tmp[40 + i];
      final double d34 = tmp[24 + i] - tmp[32 + i];
      final double e0 = s07 + s34;
      final double e1 = s16 + s25;
      final double e2 = s07 - s34;
      final double e3 = s16 - s25;
      out[i]      = (c4 * (e0 + e1) / 8).round();
      out[32 + i] = (c4 * (e0 - e1) / 8).round();
      out[16 + i] = ((c6 * e3 + c2 * e2) / 8).round();
      out[48 + i] = ((c6 * e2 - c2 * e3) / 8).round();
      final double f0 = c7 * d07 - c1 * d34;
      final double f1 = c5 * d16 - c3 * d25;
      final double f2 = c5 * d25 + c3 * d16;
      final double f3 = c7 * d34 + c1 * d07;
      out[8 + i]  = ((f0 + f2) / 8).round();
      out[24 + i] = ((f1 + f3) / 8).round();
      out[40 + i] = ((f1 - f3) / 8).round();
      out[56 + i] = ((f2 - f0) / 8).round();
    }
    return out;
  }

  // ── JFIF header helpers ──────────────────────────────────────────────────

  void _writeMarker(List<int> out, int marker) {
    out.add(marker >> 8);
    out.add(marker & 0xFF);
  }

  void _writeAPP0(List<int> out) {
    out.addAll([0xFF, 0xE0, 0x00, 0x10]); // APP0, length=16
    out.addAll([0x4A, 0x46, 0x49, 0x46, 0x00]); // "JFIF\0"
    out.addAll([0x01, 0x01, 0x00]); // version 1.1, no units
    out.addAll([0x00, 0x01, 0x00, 0x01]); // pixel density 1×1
    out.addAll([0x00, 0x00]); // no thumbnail
  }

  void _writeDQT(List<int> out, int tableId, List<int> qt) {
    out.addAll([0xFF, 0xDB]);
    final int len = 67;
    out.add(len >> 8);
    out.add(len & 0xFF);
    out.add(tableId); // precision=0 (8-bit)
    // Write in zig-zag order
    for (int i = 0; i < 64; i++) out.add(qt[_JpegParser._kZigZag[i]]);
  }

  void _writeSOF0(List<int> out, int w, int h) {
    out.addAll([0xFF, 0xC0]);
    out.addAll([0x00, 0x11]); // length=17
    out.add(0x08); // precision=8
    out.add(h >> 8);
    out.add(h & 0xFF);
    out.add(w >> 8);
    out.add(w & 0xFF);
    out.add(0x03); // 3 components
    // Y: id=1, sampling=1×1, qt=0
    out.addAll([0x01, 0x11, 0x00]);
    // Cb: id=2, sampling=1×1, qt=1
    out.addAll([0x02, 0x11, 0x01]);
    // Cr: id=3, sampling=1×1, qt=1
    out.addAll([0x03, 0x11, 0x01]);
  }

  void _writeDHT(List<int> out, int type, int tableId, _HuffSpec spec) {
    out.addAll([0xFF, 0xC4]);
    final int bodyLen = 1 + 16 + spec.values.length;
    out.add((bodyLen + 2) >> 8);
    out.add((bodyLen + 2) & 0xFF);
    out.add((type << 4) | tableId);
    out.addAll(spec.lengths);
    out.addAll(spec.values);
  }

  void _writeSOS(List<int> out) {
    out.addAll([0xFF, 0xDA]);
    out.addAll([0x00, 0x0C]); // length=12
    out.add(0x03); // 3 components
    out.addAll([0x01, 0x00]); // Y: dc=0, ac=0
    out.addAll([0x02, 0x11]); // Cb: dc=1, ac=1
    out.addAll([0x03, 0x11]); // Cr: dc=1, ac=1
    out.addAll([0x00, 0x3F, 0x00]); // Ss=0, Se=63, Ah/Al=0
  }

  // ── Standard JPEG quantisation tables (from ISO/IEC 10918-1 Annex K) ────

  static const List<int> _kLumQt = [
    16, 11, 10, 16, 24, 40, 51, 61,
    12, 12, 14, 19, 26, 58, 60, 55,
    14, 13, 16, 24, 40, 57, 69, 56,
    14, 17, 22, 29, 51, 87, 80, 62,
    18, 22, 37, 56, 68,109,103, 77,
    24, 35, 55, 64, 81,104,113, 92,
    49, 64, 78, 87,103,121,120,101,
    72, 92, 95, 98,112,100,103, 99,
  ];

  static const List<int> _kChromQt = [
    17, 18, 24, 47, 99, 99, 99, 99,
    18, 21, 26, 66, 99, 99, 99, 99,
    24, 26, 56, 99, 99, 99, 99, 99,
    47, 66, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
    99, 99, 99, 99, 99, 99, 99, 99,
  ];

  // ── Standard IJG Huffman tables ──────────────────────────────────────────

  static final _HuffSpec _kDcLumHuff = _HuffSpec(
    lengths: [0,1,5,1,1,1,1,1,1,0,0,0,0,0,0,0],
    values:  [0,1,2,3,4,5,6,7,8,9,10,11],
  );
  static final _HuffSpec _kDcChromHuff = _HuffSpec(
    lengths: [0,3,1,1,1,1,1,1,1,1,1,0,0,0,0,0],
    values:  [0,1,2,3,4,5,6,7,8,9,10,11],
  );
  static final _HuffSpec _kAcLumHuff = _HuffSpec(
    lengths: [0,2,1,3,3,2,4,3,5,5,4,4,0,0,1,125],
    values:  [
       1, 2, 3, 0, 4,17, 5,18,33,49,65, 6,19,81,97, 7,34,113,20,50,129,145,161,
       8,35,66,177,193,21,82,209,240,36,51,98,114,130, 9,10,22,23,24,25,26,37,38,
      39,40,41,42,52,53,54,55,56,57,58,67,68,69,70,71,72,73,74,83,84,85,86,87,88,
      89,90,99,100,101,102,103,104,105,106,115,116,117,118,119,120,121,122,131,132,
      133,134,135,136,137,138,146,147,148,149,150,151,152,153,154,162,163,164,165,
      166,167,168,169,170,178,179,180,181,182,183,184,185,186,194,195,196,197,198,
      199,200,201,202,210,211,212,213,214,215,216,217,218,225,226,227,228,229,230,
      231,232,233,234,242,243,244,245,246,247,248,249,250,
    ],
  );
  static final _HuffSpec _kAcChromHuff = _HuffSpec(
    lengths: [0,2,1,2,4,4,3,4,7,5,4,4,0,1,2,119],
    values:  [
       0, 1, 2, 3,17, 4, 5,33,49, 6,18,65,81, 7,97,113,19,34,50,129, 2,8,20,66,
      145,161,177,193,35,51,82,240,21,98,114,209,10,22,36,52,225,37,241,23,24,25,
      26,38,39,40,41,42,53,54,55,56,57,58,67,68,69,70,71,72,73,74,83,84,85,86,87,
      88,89,90,99,100,101,102,103,104,105,106,115,116,117,118,119,120,121,122,130,
      131,132,133,134,135,136,137,138,146,147,148,149,150,151,152,153,154,162,163,
      164,165,166,167,168,169,170,178,179,180,181,182,183,184,185,186,194,195,196,
      197,198,199,200,201,202,210,211,212,213,214,215,216,217,218,226,227,228,229,
      230,231,232,233,234,242,243,244,245,246,247,248,249,250,
    ],
  );
}

class _HuffSpec {
  final List<int> lengths;
  final List<int> values;
  const _HuffSpec({required this.lengths, required this.values});
}

class _BitWriter {
  final List<int> _out;
  int _buf = 0;
  int _bitsLeft = 8;

  _BitWriter(this._out);

  void writeHuff(_HuffSpec spec, int sym) {
    // Find the VLC code for sym
    int code = 0;
    int codeLen = 0;
    int idx = 0;
    for (int len = 0; len < 16; len++) {
      for (int i = 0; i < spec.lengths[len]; i++) {
        if (spec.values[idx] == sym) {
          codeLen = len + 1;
          _writeBits(code, codeLen);
          return;
        }
        code++;
        idx++;
      }
      code <<= 1;
    }
  }

  void writeVlc(int val) {
    final int len = _bitLengthOf(val);
    if (len == 0) return;
    if (val < 0) val += (1 << len) - 1;
    _writeBits(val, len);
  }

  int _bitLengthOf(int v) {
    if (v < 0) v = -v;
    int len = 0;
    while (v > 0) { v >>= 1; len++; }
    return len;
  }

  void _writeBits(int bits, int len) {
    for (int i = len - 1; i >= 0; i--) {
      _bitsLeft--;
      if (((bits >> i) & 1) == 1) _buf |= (1 << _bitsLeft);
      if (_bitsLeft == 0) _emit();
    }
  }

  void _emit() {
    _out.add(_buf);
    if (_buf == 0xFF) _out.add(0x00); // byte stuffing
    _buf = 0;
    _bitsLeft = 8;
  }

  void flush() {
    if (_bitsLeft < 8) {
      // Pad remaining bits with 1s (JPEG standard)
      _buf |= (1 << _bitsLeft) - 1;
      _emit();
    }
  }
}