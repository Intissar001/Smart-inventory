import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;

// OCR + medicine matching
import '../features/ocr/services/ocr_service.dart';
import '../features/ocr/services/medicine_matcher_service.dart';
import '../features/ocr/models/ocr_result.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────────────────────────────────────

class DetectedBox {
  final int id;
  double x1, y1, x2, y2; // pixel coords in ORIGINAL image space
  String label;
  double confidence;
  bool isManual; // true = added by user, not by YOLO

  DetectedBox({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.label,
    required this.confidence,
    this.isManual = false,
  });

  double get width => x2 - x1;
  double get height => y2 - y1;

  DetectedBox copyWith({
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    String? label,
    double? confidence,
  }) =>
      DetectedBox(
        id: id,
        x1: x1 ?? this.x1,
        y1: y1 ?? this.y1,
        x2: x2 ?? this.x2,
        y2: y2 ?? this.y2,
        label: label ?? this.label,
        confidence: confidence ?? this.confidence,
        isManual: isManual,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Camera Scan Screen
// ─────────────────────────────────────────────────────────────────────────────

class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  bool _flashEnabled = false;
  bool _isSending = false;

  // ── Flash helpers ─────────────────────────────────────────────────────────

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final next = !_flashEnabled;
    try {
      await _controller!.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flashEnabled = next);
    } catch (e) {
      debugPrint("Flash toggle error: $e");
    }
  }

  Future<void> _turnFlashOff() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_flashEnabled) return; // already off, nothing to do
    try {
      await _controller!.setFlashMode(FlashMode.off);
      setState(() => _flashEnabled = false);
    } catch (e) {
      debugPrint("Flash off error: $e");
    }
  }

  late AnimationController _pulseController;

  // ⚠️  Change this to your PC's local IP when using a physical device.
  //     For Android emulator keep http://10.0.2.2:8000/detect
  static const String _backendUrl = "http://192.168.1.2:8000/detect";

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      _controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      _initializeControllerFuture = _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Camera Error: $e");
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  // ── Capture → send → navigate ─────────────────────────────────────────────

  Future<void> _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isSending) return;

    try {
      final XFile xFile = await _controller!.takePicture();
      // Auto-turn flash off immediately after capture
      await _turnFlashOff();

      final File file = File(xFile.path);

      // Decode to ui.Image — this preserves original pixel dimensions
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      setState(() => _isSending = true);

      // Send to backend
      final request =
          http.MultipartRequest('POST', Uri.parse(_backendUrl));
      request.files
          .add(await http.MultipartFile.fromPath('file', file.path));

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        _showError("Backend error ${response.statusCode}");
        return;
      }

      final json = jsonDecode(body);
      final List<dynamic> detections = json['detections'] ?? [];
      final double imgW = (json['image_width'] as num).toDouble();
      final double imgH = (json['image_height'] as num).toDouble();

      final List<DetectedBox> boxes = detections.asMap().entries.map((e) {
        final d = e.value;
        final bbox = d['bbox'] as List<dynamic>;
        return DetectedBox(
          id: e.key,
          x1: (bbox[0] as num).toDouble(),
          y1: (bbox[1] as num).toDouble(),
          x2: (bbox[2] as num).toDouble(),
          y2: (bbox[3] as num).toDouble(),
          label: d['label'] ?? 'Object',
          confidence: (d['confidence'] as num).toDouble(),
        );
      }).toList();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AnnotationEditorScreen(
              capturedImage: uiImage,
              imageFile: file,
              detectedBoxes: boxes,
              imageWidth: imgW,
              imageHeight: imgH,
              backendBase: _backendUrl.replaceAll('/detect', ''),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Capture error: $e");
      _showError("Impossible de contacter le backend.\nVérifie l'IP.");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.red.shade700,
      duration: const Duration(seconds: 4),
    ));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            _buildCamera(),
            _buildGrid(),
            _buildFocusBox(),
            _buildHeader(),
            _buildCaptureButton(),
            if (_isSending) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildCamera() {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.done &&
            _controller != null) {
          return SizedBox.expand(child: CameraPreview(_controller!));
        }
        return const Center(
            child: CircularProgressIndicator(color: Colors.white));
      },
    );
  }

  Widget _buildGrid() => Positioned.fill(
        child: IgnorePointer(child: CustomPaint(painter: _GridPainter())),
      );

  Widget _buildFocusBox() {
    const side = 16.0;
    const border = BorderSide(color: Color(0xFF14B8A6), width: 4);
    return Center(
      child: IgnorePointer(
        child: Container(
          width: 256,
          height: 256,
          decoration: BoxDecoration(
            border:
                Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Stack(children: [
            Positioned(
                top: -1,
                left: -1,
                child: _corner(
                    const BoxDecoration(border: Border(top: border, left: border)),
                    side)),
            Positioned(
                top: -1,
                right: -1,
                child: _corner(
                    const BoxDecoration(
                        border: Border(top: border, right: border)),
                    side)),
            Positioned(
                bottom: -1,
                left: -1,
                child: _corner(
                    const BoxDecoration(
                        border: Border(bottom: border, left: border)),
                    side)),
            Positioned(
                bottom: -1,
                right: -1,
                child: _corner(
                    const BoxDecoration(
                        border: Border(bottom: border, right: border)),
                    side)),
          ]),
        ),
      ),
    );
  }

  Widget _corner(BoxDecoration deco, double s) =>
      Container(width: s, height: s, decoration: deco);

  Widget _buildHeader() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withOpacity(0.8), Colors.transparent],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _iconBtn(Icons.arrow_back, () => Navigator.pop(context)),
            _iconBtn(
              _flashEnabled ? Icons.flash_on : Icons.flash_off,
              _toggleFlash,
              color: _flashEnabled ? const Color(0xFFFBBF24) : Colors.white,
              bg: _flashEnabled
                  ? const Color(0xFFFBBF24).withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap,
      {Color color = Colors.white, Color? bg}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg ?? Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.9),
              Colors.black.withOpacity(0.7),
              Colors.transparent,
            ],
          ),
        ),
        child: GestureDetector(
          onTap: _isSending ? null : _handleCapture,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _isSending
                      ? [Colors.grey.shade700, Colors.grey.shade600]
                      : [const Color(0xFF2563EB), const Color(0xFF0D9488)],
                ),
                borderRadius: BorderRadius.circular(24),
                border:
                    Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withOpacity(
                        _isSending ? 0.1 : 0.5 + _pulseController.value * 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      _isSending ? Icons.hourglass_empty : Icons.camera_alt,
                      color: Colors.white,
                      size: 32),
                  const SizedBox(width: 12),
                  Text(
                    _isSending ? "Analyse en cours..." : "Capture Scan",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.6),
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF14B8A6)),
                SizedBox(height: 16),
                Text("Analyse YOLO...",
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Annotation Editor Screen
// Full-size image + interactive bounding boxes (move / resize / add / delete)
// ─────────────────────────────────────────────────────────────────────────────

class AnnotationEditorScreen extends StatefulWidget {
  final ui.Image capturedImage;
  final File imageFile;
  final List<DetectedBox> detectedBoxes;
  final double imageWidth;
  final double imageHeight;
  final String backendBase; // e.g. "http://192.168.1.3:8000"

  const AnnotationEditorScreen({
    super.key,
    required this.capturedImage,
    required this.imageFile,
    required this.detectedBoxes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backendBase,
  });

  @override
  State<AnnotationEditorScreen> createState() =>
      _AnnotationEditorScreenState();
}

// Possible interactions with a box handle
enum _Handle { none, move, resizeTL, resizeTR, resizeBL, resizeBR }

class _AnnotationEditorScreenState extends State<AnnotationEditorScreen> {
  late List<DetectedBox> _boxes;
  int? _selectedId;
  bool _isDrawing = false; // drawing a new box
  Offset? _drawStart;
  Rect? _drawRect;

  // For dragging / resizing
  _Handle _activeHandle = _Handle.none;
  Offset? _lastPan;

  int _nextId = 0;

  // The rendered image container key (to get its size)
  final GlobalKey _imageKey = GlobalKey();
  Size _containerSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _boxes = List.from(widget.detectedBoxes);
    _nextId =
        (_boxes.isEmpty ? 0 : _boxes.map((b) => b.id).reduce(max)) + 1;
  }

  // ── Coordinate helpers ────────────────────────────────────────────────────

  /// Scale a pixel value from image space → container space
  double _sx(double x) => x * _containerSize.width / widget.imageWidth;
  double _sy(double y) => y * _containerSize.height / widget.imageHeight;

  /// Scale from container space → image space
  double _ix(double x) => x * widget.imageWidth / _containerSize.width;
  double _iy(double y) => y * widget.imageHeight / _containerSize.height;

  void _updateContainerSize() {
    final box = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null) {
      final s = box.size;
      if (s != _containerSize) setState(() => _containerSize = s);
    }
  }

  // ── Hit testing ───────────────────────────────────────────────────────────

  static const double _handleRadius = 14.0;

  _Handle _hitHandle(DetectedBox b, Offset local) {
    final corners = {
      _Handle.resizeTL: Offset(_sx(b.x1), _sy(b.y1)),
      _Handle.resizeTR: Offset(_sx(b.x2), _sy(b.y1)),
      _Handle.resizeBL: Offset(_sx(b.x1), _sy(b.y2)),
      _Handle.resizeBR: Offset(_sx(b.x2), _sy(b.y2)),
    };
    for (final e in corners.entries) {
      if ((local - e.value).distance < _handleRadius) return e.key;
    }
    final rect = Rect.fromLTRB(
        _sx(b.x1), _sy(b.y1), _sx(b.x2), _sy(b.y2));
    if (rect.contains(local)) return _Handle.move;
    return _Handle.none;
  }

  DetectedBox? _boxAt(Offset local) {
    // Prefer selected box first
    if (_selectedId != null) {
      final sel = _boxes.firstWhere((b) => b.id == _selectedId,
          orElse: () => _boxes.first);
      if (_hitHandle(sel, local) != _Handle.none) return sel;
    }
    for (final b in _boxes.reversed) {
      if (_hitHandle(b, local) != _Handle.none) return b;
    }
    return null;
  }

  // ── Gesture handlers ──────────────────────────────────────────────────────

  void _onTapDown(TapDownDetails d) {
    _updateContainerSize();
    final local = d.localPosition;
    final hit = _boxAt(local);
    setState(() {
      if (hit != null) {
        _selectedId = hit.id;
      } else {
        _selectedId = null;
      }
    });
  }

  void _onPanStart(DragStartDetails d) {
    _updateContainerSize();
    if (_isDrawing) {
      _drawStart = d.localPosition;
      setState(() => _drawRect = Rect.fromLTWH(
          d.localPosition.dx, d.localPosition.dy, 0, 0));
      return;
    }
    final local = d.localPosition;
    final hit = _boxAt(local);
    if (hit != null) {
      _activeHandle = _hitHandle(hit, local);
      setState(() => _selectedId = hit.id);
    }
    _lastPan = local;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isDrawing && _drawStart != null) {
      setState(() {
        _drawRect = Rect.fromPoints(_drawStart!, d.localPosition);
      });
      return;
    }
    if (_selectedId == null || _lastPan == null) return;

    final idx = _boxes.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;

    final dx = d.localPosition.dx - _lastPan!.dx;
    final dy = d.localPosition.dy - _lastPan!.dy;
    // Convert delta to image space
    final dxi = _ix(dx) - _ix(0);
    final dyi = _iy(dy) - _iy(0);

    final b = _boxes[idx];
    DetectedBox updated;

    switch (_activeHandle) {
      case _Handle.move:
        updated = b.copyWith(
          x1: (b.x1 + dxi).clamp(0, widget.imageWidth - 10),
          y1: (b.y1 + dyi).clamp(0, widget.imageHeight - 10),
          x2: (b.x2 + dxi).clamp(10, widget.imageWidth),
          y2: (b.y2 + dyi).clamp(10, widget.imageHeight),
        );
        break;
      case _Handle.resizeTL:
        updated = b.copyWith(
          x1: (b.x1 + dxi).clamp(0, b.x2 - 10),
          y1: (b.y1 + dyi).clamp(0, b.y2 - 10),
        );
        break;
      case _Handle.resizeTR:
        updated = b.copyWith(
          x2: (b.x2 + dxi).clamp(b.x1 + 10, widget.imageWidth),
          y1: (b.y1 + dyi).clamp(0, b.y2 - 10),
        );
        break;
      case _Handle.resizeBL:
        updated = b.copyWith(
          x1: (b.x1 + dxi).clamp(0, b.x2 - 10),
          y2: (b.y2 + dyi).clamp(b.y1 + 10, widget.imageHeight),
        );
        break;
      case _Handle.resizeBR:
        updated = b.copyWith(
          x2: (b.x2 + dxi).clamp(b.x1 + 10, widget.imageWidth),
          y2: (b.y2 + dyi).clamp(b.y1 + 10, widget.imageHeight),
        );
        break;
      case _Handle.none:
        return;
    }

    setState(() {
      _boxes[idx] = updated;
      _lastPan = d.localPosition;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    if (_isDrawing && _drawRect != null && _drawRect!.width > 10) {
      // Convert draw rect to image coords
      final x1 = _ix(_drawRect!.left);
      final y1 = _iy(_drawRect!.top);
      final x2 = _ix(_drawRect!.right);
      final y2 = _iy(_drawRect!.bottom);
      final newBox = DetectedBox(
        id: _nextId++,
        x1: x1.clamp(0, widget.imageWidth),
        y1: y1.clamp(0, widget.imageHeight),
        x2: x2.clamp(0, widget.imageWidth),
        y2: y2.clamp(0, widget.imageHeight),
        label: "medicine",
        confidence: 1.0,
        isManual: true,
      );
      setState(() {
        _boxes.add(newBox);
        _selectedId = newBox.id;
        _drawRect = null;
        _isDrawing = false;
      });
    } else {
      setState(() {
        _drawRect = null;
        if (_isDrawing) _isDrawing = false;
      });
    }
    _activeHandle = _Handle.none;
    _lastPan = null;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  void _deleteSelected() {
    if (_selectedId == null) return;
    setState(() {
      _boxes.removeWhere((b) => b.id == _selectedId);
      _selectedId = null;
    });
  }

  void _renameSelected() async {
    if (_selectedId == null) return;
    final idx = _boxes.indexWhere((b) => b.id == _selectedId);
    if (idx < 0) return;
    final ctrl = TextEditingController(text: _boxes[idx].label);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Rename label"),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: "Label")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text),
              child: const Text("Save")),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _boxes[idx] = _boxes[idx].copyWith(label: result));
    }
  }

  Future<void> _confirmAndSave() async {
    // Navigate to results screen
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanResultsScreen(
          detectedBoxes: _boxes,
          capturedImage: widget.capturedImage,
          imageFile: widget.imageFile,
          imageWidth: widget.imageWidth,
          imageHeight: widget.imageHeight,
          backendBase: widget.backendBase,
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        foregroundColor: Colors.white,
        title: Text(
          "${_boxes.length} box${_boxes.length == 1 ? '' : 'es'} detected",
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          // Toggle draw mode
          IconButton(
            icon: Icon(
              Icons.add_box_outlined,
              color: _isDrawing ? const Color(0xFF14B8A6) : Colors.white54,
            ),
            tooltip: "Draw new box",
            onPressed: () => setState(() {
              _isDrawing = !_isDrawing;
              _selectedId = null;
            }),
          ),
          if (_selectedId != null) ...[
            IconButton(
              icon: const Icon(Icons.label_outline, color: Colors.white70),
              tooltip: "Rename",
              onPressed: _renameSelected,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: "Delete box",
              onPressed: _deleteSelected,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_isDrawing)
            Container(
              color: const Color(0xFF14B8A6).withOpacity(0.15),
              padding:
                  const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.touch_app, color: Color(0xFF14B8A6), size: 16),
                  SizedBox(width: 8),
                  Text(
                    "Draw mode — drag to add a new box",
                    style: TextStyle(
                        color: Color(0xFF14B8A6), fontSize: 13),
                  ),
                ],
              ),
            ),
          Expanded(
            child: GestureDetector(
              onTapDown: _onTapDown,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  // Measure container after first frame
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _updateContainerSize());
                  return Stack(
                    key: _imageKey,
                    children: [
                      // ── Full-size image (BoxFit.contain keeps aspect ratio) ──
                      Positioned.fill(
                        child: RawImage(
                          image: widget.capturedImage,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                      // ── Bounding boxes ──────────────────────────────────────
                      if (_containerSize != Size.zero)
                        ..._boxes.map((b) =>
                            _buildBox(b, constraints)),
                      // ── In-progress draw rect ───────────────────────────────
                      if (_drawRect != null)
                        Positioned(
                          left: _drawRect!.left,
                          top: _drawRect!.top,
                          width: _drawRect!.width.abs(),
                          height: _drawRect!.height.abs(),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colors.yellow, width: 2),
                              color: Colors.yellow.withOpacity(0.1),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildBox(DetectedBox b, BoxConstraints constraints) {
    // Map image coords → container coords
    // We use BoxFit.contain so we need to account for letterboxing
    final imgAspect = widget.imageWidth / widget.imageHeight;
    final cW = constraints.maxWidth;
    final cH = constraints.maxHeight;
    final cAspect = cW / cH;

    double renderedW, renderedH, offsetX, offsetY;
    if (imgAspect > cAspect) {
      // Letterbox top/bottom
      renderedW = cW;
      renderedH = cW / imgAspect;
      offsetX = 0;
      offsetY = (cH - renderedH) / 2;
    } else {
      // Letterbox left/right
      renderedH = cH;
      renderedW = cH * imgAspect;
      offsetX = (cW - renderedW) / 2;
      offsetY = 0;
    }

    final scaleX = renderedW / widget.imageWidth;
    final scaleY = renderedH / widget.imageHeight;

    final left = offsetX + b.x1 * scaleX;
    final top = offsetY + b.y1 * scaleY;
    final w = b.width * scaleX;
    final h = b.height * scaleY;

    final isSelected = b.id == _selectedId;
    final boxColor =
        b.isManual ? Colors.yellowAccent : const Color(0xFF14B8A6);

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Box border
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: isSelected ? Colors.white : boxColor, width: isSelected ? 3 : 2),
              borderRadius: BorderRadius.circular(3),
              color: isSelected
                  ? Colors.white.withOpacity(0.08)
                  : boxColor.withOpacity(0.05),
            ),
          ),
          // Label badge (top-left, outside box)
          Positioned(
            top: -22,
            left: 0,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: b.isManual
                      ? [Colors.amber.shade700, Colors.amber.shade500]
                      : [const Color(0xFF14B8A6), const Color(0xFF0D9488)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "${b.isManual ? '✏ ' : ''}${b.label}  ${(b.confidence * 100).round()}%",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          // Corner handles (only when selected)
          if (isSelected) ...[
            _handle(-_handleRadius / 2, -_handleRadius / 2, boxColor),
            _handle(w - _handleRadius / 2, -_handleRadius / 2, boxColor),
            _handle(-_handleRadius / 2, h - _handleRadius / 2, boxColor),
            _handle(w - _handleRadius / 2, h - _handleRadius / 2, boxColor),
          ],
        ],
      ),
    );
  }

  Widget _handle(double l, double t, Color c) => Positioned(
        left: l,
        top: t,
        child: Container(
          width: _handleRadius,
          height: _handleRadius,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: c, width: 2),
          ),
        ),
      );

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text("Rescan"),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check_circle_outline),
              label: Text("Confirm  (${_boxes.length})"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _confirmAndSave,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scan Results Screen
// Shows per-box crops + total count + shelf editor
// ─────────────────────────────────────────────────────────────────────────────

class ScanResultsScreen extends StatefulWidget {
  final List<DetectedBox> detectedBoxes;
  final ui.Image capturedImage;
  final File imageFile;
  final double imageWidth;
  final double imageHeight;
  final String backendBase;

  const ScanResultsScreen({
    super.key,
    required this.detectedBoxes,
    required this.capturedImage,
    required this.imageFile,
    required this.imageWidth,
    required this.imageHeight,
    required this.backendBase,
  });

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen>
    with TickerProviderStateMixin {
  late int _count;
  String _shelfName = "Shelf A";
  bool _isEditingShelf = false;
  final TextEditingController _shelfCtrl = TextEditingController();

  bool _showSuccess = false;
  late AnimationController _successAnim;
  late Animation<Offset> _slideAnim;

  // Crops fetched from /crop endpoint — key = box.id
  final Map<int, Uint8List?> _crops = {};
  bool _loadingCrops = false;

  // OCR results — key = box.id
  final Map<int, OcrResult?> _ocrResults = {};

  final OCRService _ocrService = OCRService();
  final MedicineMatcherService _matcher = MedicineMatcherService();

  @override
  void initState() {
    super.initState();
    _count = widget.detectedBoxes.length;
    _shelfCtrl.text = _shelfName;

    _successAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 1.5), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _successAnim, curve: Curves.elasticOut));

    _loadMatcherAndFetchCrops();
  }

  @override
  void dispose() {
    _shelfCtrl.dispose();
    _successAnim.dispose();
    OCRService.disposeRecognizer();
    super.dispose();
  }

  // ── Load medicine list, then fetch crops + run OCR ───────────────────────

  Future<void> _loadMatcherAndFetchCrops() async {
    try {
      await _matcher.load();
    } catch (e) {
      debugPrint("MedicineMatcherService load error: $e");
    }
    await _fetchCrops();
  }

  Future<void> _fetchCrops() async {
    setState(() => _loadingCrops = true);
    for (final box in widget.detectedBoxes) {
      try {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse("${widget.backendBase}/crop"),
        );
        request.files.add(
            await http.MultipartFile.fromPath('file', widget.imageFile.path));
        request.fields['bbox'] =
            jsonEncode([box.x1.round(), box.y1.round(), box.x2.round(), box.y2.round()]);
        request.fields['padding'] = '6';

        final resp = await request.send();
        if (resp.statusCode == 200) {
          final bytes = await resp.stream.toBytes();
          if (mounted) {
            setState(() => _crops[box.id] = bytes);
          }
          // Run OCR on this crop in the background
          _runOcrOnCrop(box.id, bytes);
        } else {
          if (mounted) setState(() => _crops[box.id] = null);
        }
      } catch (e) {
        debugPrint("Crop error for box ${box.id}: $e");
        if (mounted) setState(() => _crops[box.id] = null);
      }
    }
    if (mounted) setState(() => _loadingCrops = false);
  }

  // ── Run ML Kit OCR on a single crop, then parse name/form/dosage ──────────

  Future<void> _runOcrOnCrop(int boxId, Uint8List bytes) async {
    try {
      // Get raw OCR text + largest visual word from ML Kit
      final OcrRawResult raw =
          await _ocrService.processBytesRich(bytes, tag: 'box_$boxId');

      // Run the matcher to extract form and dosage.
      // Name matching (DB lookup) stays disabled — we keep matchedName: null
      // and fall back to the largest visual text for display, exactly as before.
      final OcrResult parsed = _matcher.parse(raw.fullText);

      final OcrResult result = OcrResult(
        matchedName: null,          // DB name matching intentionally off
        form: parsed.form,          // ← form extracted from OCR text
        dosage: parsed.dosage,      // ← dosage extracted from OCR text
        rawText: raw.fullText,
        confidence: 0.0,
        largestText: raw.largestText,
      );

      if (mounted) setState(() => _ocrResults[boxId] = result);
    } catch (e) {
      debugPrint("OCR error for box $boxId: $e");
      if (mounted) setState(() => _ocrResults[boxId] = null);
    }
  }

  void _confirmSave() {
    setState(() => _showSuccess = true);
    _successAnim.forward();
    Future.delayed(
        const Duration(milliseconds: 2500), () => Navigator.pop(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      _buildShelfEditor(),
                      const SizedBox(height: 20),
                      _buildImageThumbnail(),
                      const SizedBox(height: 20),
                      _buildCountCard(),
                      const SizedBox(height: 16),
                      _buildCountAdjust(),
                      const SizedBox(height: 24),
                      _buildCropsGrid(),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBottomButtons(),
          if (_showSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const Text("Scan Results",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
          ],
        ),
      );

  Widget _buildShelfEditor() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Row(children: [
          const Icon(Icons.shelves, color: Color(0xFF2563EB)),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditingShelf
                ? TextField(
                    controller: _shelfCtrl,
                    decoration: const InputDecoration(isDense: true))
                : Text(_shelfName,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: Icon(_isEditingShelf ? Icons.check : Icons.edit),
            onPressed: () => setState(() {
              if (_isEditingShelf) _shelfName = _shelfCtrl.text;
              _isEditingShelf = !_isEditingShelf;
            }),
          ),
        ]),
      );

  Widget _buildImageThumbnail() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1E293B),
      ),
      clipBehavior: Clip.antiAlias,
      child: RawImage(
        image: widget.capturedImage,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }

  Widget _buildCountCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(children: [
          const Text("Total Boxes Detected",
              style: TextStyle(color: Colors.white70)),
          Text("$_count",
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _buildCountAdjust() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _circleBtn(
              Icons.remove, Colors.red, () => setState(() => _count = max(0, _count - 1))),
          const SizedBox(width: 24),
          Text("$_count",
              style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
          const SizedBox(width: 24),
          _circleBtn(
              Icons.add, Colors.green, () => setState(() => _count++)),
        ],
      );

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(20)),
          child: Icon(icon, color: Colors.white),
        ),
      );

  // ── Crops grid ────────────────────────────────────────────────────────────

  Widget _buildCropsGrid() {
    if (widget.detectedBoxes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text("Detected Boxes",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (_loadingCrops)
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Color(0xFF14B8A6))),
        ]),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.75,
          ),
          itemCount: widget.detectedBoxes.length,
          itemBuilder: (_, i) {
            final b = widget.detectedBoxes[i];
            final cropBytes = _crops[b.id];
            final ocrResult = _ocrResults[b.id];
            final ocrDone = _ocrResults.containsKey(b.id);
            return _buildCropCard(b, cropBytes, ocrResult: ocrResult, ocrDone: ocrDone);
          },
        ),
      ],
    );
  }

  Widget _buildCropCard(DetectedBox b, Uint8List? bytes,
      {OcrResult? ocrResult, bool ocrDone = false}) {
    final bool ocrLoading = bytes != null && !ocrDone;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Crop image (tap → raw OCR debug sheet) ──────────────────
          Expanded(
            child: GestureDetector(
              onTap: ocrDone
                  ? () => _showRawOcrSheet(
                        context,
                        boxId: b.id,
                        label: b.label,
                        bytes: bytes,
                        ocrResult: ocrResult,
                      )
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  bytes != null
                      ? Image.memory(bytes, fit: BoxFit.cover)
                      : Container(
                          color: const Color(0xFF1E293B),
                          child: const Center(
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF14B8A6))),
                          ),
                        ),
                  // Small "tap to inspect" hint once OCR is done
                  if (ocrDone)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.text_snippet_outlined,
                            size: 11, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ── Info panel ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 7, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // YOLO confidence badge
                Row(
                  children: [
                    Expanded(
                      child: Text(b.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF14B8A6).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        "${(b.confidence * 100).round()}%",
                        style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F9688)),
                      ),
                    ),
                  ],
                ),

                // ── OCR loading indicator ────────────────────────────────
                if (ocrLoading) ...[
                  const SizedBox(height: 5),
                  Row(children: const [
                    SizedBox(
                        width: 9,
                        height: 9,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: Color(0xFF6366F1))),
                    SizedBox(width: 5),
                    Text("Lecture OCR...",
                        style:
                            TextStyle(fontSize: 9, color: Color(0xFF6366F1))),
                  ]),
                ],

                // ── OCR results ──────────────────────────────────────────
                if (ocrDone && ocrResult != null) ...[
                  const SizedBox(height: 5),
                  const Divider(height: 1, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 4),

                  // Medicine name — DB match OR largest visual text fallback
                  if (ocrResult.hasName) ...[
                    // ✅ Matched in database
                    _ocrRow(
                      icon: Icons.medication_outlined,
                      iconColor: const Color(0xFF6366F1),
                      label: ocrResult.matchedName!,
                      labelStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B)),
                    ),
                  ] else if (ocrResult.hasLargestText) ...[
                    // 📝 Fallback — largest text on the box (brand name heuristic)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.text_fields_rounded,
                            size: 11, color: Color(0xFFF97316)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            ocrResult.largestText!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF97316),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF97316).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('OCR',
                              style: TextStyle(
                                  fontSize: 7,
                                  color: Color(0xFFF97316),
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ] else ...[
                    _ocrRow(
                      icon: Icons.medication_outlined,
                      iconColor: const Color(0xFF6366F1),
                      label: '—',
                      labelStyle:
                          const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 3),

                  // Form / type
                  _ocrRow(
                    icon: Icons.category_outlined,
                    iconColor: const Color(0xFF0EA5E9),
                    label: ocrResult.hasForm ? ocrResult.form! : '—',
                    labelStyle: TextStyle(
                        fontSize: 9,
                        color: ocrResult.hasForm
                            ? const Color(0xFF475569)
                            : Colors.grey),
                  ),
                  const SizedBox(height: 3),

                  // Dosage
                  _ocrRow(
                    icon: Icons.science_outlined,
                    iconColor: const Color(0xFFF59E0B),
                    label: ocrResult.hasDosage ? ocrResult.dosage! : '—',
                    labelStyle: TextStyle(
                        fontSize: 9,
                        color: ocrResult.hasDosage
                            ? const Color(0xFF475569)
                            : Colors.grey),
                  ),

                  // Fallback warning
                  if (ocrResult.isFallback) ...[
                    const SizedBox(height: 3),
                    const Text(
                      '⚠ Non trouvé en base',
                      style: TextStyle(fontSize: 7, color: Colors.orange),
                    ),
                  ],
                ],

                // ── Nothing recognized at all ────────────────────────────
                if (ocrDone && ocrResult == null) ...[
                  const SizedBox(height: 4),
                  const Text("OCR: aucun texte détecté",
                      style: TextStyle(fontSize: 9, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Small icon + text row used in the OCR panel.
  Widget _ocrRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required TextStyle labelStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 11, color: iconColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: labelStyle),
        ),
      ],
    );
  }

  // ── Raw OCR debug bottom sheet ───────────────────────────────────────────

  void _showRawOcrSheet(
    BuildContext context, {
    required int boxId,
    required String label,
    required Uint8List? bytes,
    required OcrResult? ocrResult,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OcrDebugSheet(
        boxId: boxId,
        label: label,
        bytes: bytes,
        ocrResult: ocrResult,
      ),
    );
  }

  Widget _buildBottomButtons() => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          color: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _confirmSave,
              child: const Text("Confirm Result",
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text("Back to Editor", style: TextStyle(color: Colors.grey)),
            ),
          ]),
        ),
      );

  Widget _buildSuccessOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black54,
          child: Center(
            child: SlideTransition(
              position: _slideAnim,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding:
                    const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF10B981)]),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.check_circle, size: 80, color: Colors.white),
                  SizedBox(height: 20),
                  Text("SCAN CONFIRMED",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid painter (camera preview overlay)
// ─────────────────────────────────────────────────────────────────────────────

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ═════════════════════════════════════════════════════════════════════════════
// OCR Debug Bottom Sheet
// ═════════════════════════════════════════════════════════════════════════════

class _OcrDebugSheet extends StatelessWidget {
  final int boxId;
  final String label;
  final Uint8List? bytes;
  final OcrResult? ocrResult;

  const _OcrDebugSheet({
    required this.boxId,
    required this.label,
    required this.bytes,
    required this.ocrResult,
  });

  @override
  Widget build(BuildContext context) {
    final raw = ocrResult?.rawText ?? '';
    final lines = raw.isEmpty
        ? <String>[]
        : raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── Handle ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header row ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Row(
                children: [
                  // Crop thumbnail
                  if (bytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(bytes!,
                          width: 54, height: 54, fit: BoxFit.cover),
                    ),
                  if (bytes != null) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Box #$boxId — $label',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 3),
                        Text(
                          '${lines.length} ligne(s) OCR extraite(s)',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  // Copy button
                  IconButton(
                    icon: const Icon(Icons.copy_rounded,
                        color: Color(0xFF14B8A6), size: 18),
                    tooltip: 'Copier le texte brut',
                    onPressed: raw.isEmpty
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: raw));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Texte copié'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFF1E293B)),

            // ── Parsed summary strip ──────────────────────────────────────
            if (ocrResult != null)
              Container(
                color: const Color(0xFF1E293B),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    _chip(Icons.medication_outlined, const Color(0xFF6366F1),
                        ocrResult!.matchedName ?? '—'),
                    const SizedBox(width: 8),
                    _chip(Icons.category_outlined, const Color(0xFF0EA5E9),
                        ocrResult!.form ?? '—'),
                    const SizedBox(width: 8),
                    _chip(Icons.science_outlined, const Color(0xFFF59E0B),
                        ocrResult!.dosage ?? '—'),
                  ],
                ),
              ),

            const Divider(height: 1, color: Color(0xFF1E293B)),

            // ── Raw OCR lines list ────────────────────────────────────────
            Expanded(
              child: raw.isEmpty
                  ? const Center(
                      child: Text(
                        'Aucun texte extrait par ML Kit.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) => const Divider(
                          height: 1, color: Color(0xFF1E293B)),
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Line number badge
                            Container(
                              width: 22,
                              height: 22,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                lines[i],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, Color color, String text) => Expanded(
        child: Row(
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: text == '—' ? const Color(0xFF475569) : Colors.white,
                    fontSize: 10),
              ),
            ),
          ],
        ),
      );
}