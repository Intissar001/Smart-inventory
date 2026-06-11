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
import '../features/ocr/services/ocr_service.dart';
import '../features/ocr/services/medicine_matcher_service.dart';
import '../features/ocr/models/ocr_result.dart';

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

// Camera Scan Screen
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

  //Flash helpers

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

  static const String _backendUrl = "http://192.168.1.4:8000/detect";

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

  //  Capture → send → navigate

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
              final result = await Navigator.push<Map<String, dynamic>>(
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
              if (mounted && result != null) Navigator.pop(context, result);
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
      if (!mounted) return;
      final result = await Navigator.push<Map<String, dynamic>>(
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
      if (!mounted) return;
      if (result != null) Navigator.pop(context, result);
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
// Scan Results Screen — v3
//
// Architecture:
//   • ONE list of _MedicineRow objects drives everything.
//     Each row = one line in the summary table (name + form + dosage + count).
//   • Rows come from two sources:
//       – Auto-created by OCR grouping when results arrive.
//       – Manually added by the user (empty or inheriting parent name).
//   • Grouping is LIVE: after any edit or add, rows with identical
//     normalised(name+form+dosage) are automatically merged into one display
//     card with their counts summed.  Merging is display-only — the raw rows
//     are preserved so the user can split them back.
//
// "Add from parent" button (inside a card):
//   – Creates a new row with name = parent name, form = "", dosage = "".
//   – Parent card count decrements by 1 automatically (min 0).
//
// "Add empty row" card (last card in list):
//   – Creates a fully empty row (name="", form="", dosage="", count=1).
//   – No automatic decrement anywhere.
//
// Edit sheet:
//   – Inline bottom sheet per card (not per raw row) that lets the user
//     change name / form / dosage and the count for that display group.
//   – After save, the raw rows that belong to the edited group are updated.
//
// Confirm button shows the live grand total.
// ─────────────────────────────────────────────────────────────────────────────

// ── Raw row model ─────────────────────────────────────────────────────────────

class _MedicineRow {
  static int _idCounter = 0;

  final int id;          // stable identity
  String name;
  String form;
  String dosage;
  int count;             // contribution of this raw row to its display group

  _MedicineRow({
    required this.name,
    required this.form,
    required this.dosage,
    required this.count,
  }) : id = ++_idCounter;

  /// Normalised key used to group rows together.
  String get groupKey {
    String n(String s) =>
        s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return '${n(name)}||${n(form)}||${n(dosage)}';
  }
}

// ── Display-group model (derived, never stored) ───────────────────────────────

class _DisplayGroup {
  final String key;
  final String name;
  final String form;
  final String dosage;
  final int totalCount;
  final List<_MedicineRow> rows; // raw rows that belong to this group

  const _DisplayGroup({
    required this.key,
    required this.name,
    required this.form,
    required this.dosage,
    required this.totalCount,
    required this.rows,
  });
}

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

  // ── Shelf ─────────────────────────────────────────────────────────────────
  String _shelfName = "Shelf A";
  bool _isEditingShelf = false;
  final TextEditingController _shelfCtrl = TextEditingController();

  // ── Success animation ────────────────────────────────────────────────────
  bool _showSuccess = false;
  late AnimationController _successAnim;
  late Animation<Offset> _slideAnim;

  // ── OCR infrastructure ────────────────────────────────────────────────────
  bool _loadingCrops = false;
  final Map<int, OcrResult?> _ocrResults = {}; // boxId → OCR
  final OCRService _ocrService = OCRService();
  final MedicineMatcherService _matcher = MedicineMatcherService();

  // ── The single source of truth ────────────────────────────────────────────
  // One _MedicineRow per detected box, seeded empty then filled by OCR.
  // The user can also add extra rows manually.
  final List<_MedicineRow> _rows = [];

  // boxId → rowId  (so OCR can update the right row when it finishes)
  final Map<int, int> _boxToRow = {};

  // ── Colour palette for group cards ───────────────────────────────────────
  static const List<Color> _palette = [
    Color(0xFF6366F1), Color(0xFF14B8A6), Color(0xFFF59E0B), Color(0xFFEF4444),
    Color(0xFF10B981), Color(0xFF3B82F6), Color(0xFFEC4899), Color(0xFF8B5CF6),
    Color(0xFFF97316), Color(0xFF06B6D4),
  ];
  final Map<String, int> _groupColorIdx = {};
  int _nextColorIdx = 0;

  // ── Derived display groups ────────────────────────────────────────────────
  List<_DisplayGroup> get _groups {
    final Map<String, List<_MedicineRow>> buckets = {};
    for (final r in _rows) {
      buckets.putIfAbsent(r.groupKey, () => []).add(r);
    }
    // Assign palette indices for new keys
    for (final key in buckets.keys) {
      if (!_groupColorIdx.containsKey(key)) {
        _groupColorIdx[key] = _nextColorIdx % _palette.length;
        _nextColorIdx++;
      }
    }
    return buckets.entries.map((e) {
      final rep = e.value.first;
      return _DisplayGroup(
        key: e.key,
        name: rep.name,
        form: rep.form,
        dosage: rep.dosage,
        totalCount: e.value.fold(0, (s, r) => s + r.count),
        rows: e.value,
      );
    }).toList();
  }

  Color _colorForKey(String key) {
    final idx = _groupColorIdx[key] ?? 0;
    return _palette[idx % _palette.length];
  }

  int get _grandTotal => _rows.fold(0, (s, r) => s + r.count);

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _shelfCtrl.text = _shelfName;

    _successAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 1.5), end: Offset.zero).animate(
            CurvedAnimation(parent: _successAnim, curve: Curves.elasticOut));

    // Create one placeholder row per detected box
    for (final b in widget.detectedBoxes) {
      final row = _MedicineRow(name: '', form: '', dosage: '', count: 1);
      _rows.add(row);
      _boxToRow[b.id] = row.id;
    }

    _loadMatcherAndFetchCrops();
  }

  @override
  void dispose() {
    _shelfCtrl.dispose();
    _successAnim.dispose();
    OCRService.disposeRecognizer();
    super.dispose();
  }

  // ── OCR pipeline ──────────────────────────────────────────────────────────

  Future<void> _loadMatcherAndFetchCrops() async {
    try { await _matcher.load(); } catch (e) {
      debugPrint("Matcher load error: $e");
    }
    await _fetchCrops();
  }

  Future<void> _fetchCrops() async {
    if (mounted) setState(() => _loadingCrops = true);
    for (final box in widget.detectedBoxes) {
      try {
        final request = http.MultipartRequest(
          'POST', Uri.parse("${widget.backendBase}/crop"));
        request.files.add(
            await http.MultipartFile.fromPath('file', widget.imageFile.path));
        request.fields['bbox'] = jsonEncode([
          box.x1.round(), box.y1.round(), box.x2.round(), box.y2.round()]);
        request.fields['padding'] = '6';

        final resp = await request.send();
        if (resp.statusCode == 200) {
          final bytes = await resp.stream.toBytes();
          _runOcrOnCrop(box.id, bytes);
        }
      } catch (e) {
        debugPrint("Crop error box ${box.id}: $e");
      }
    }
    if (mounted) setState(() => _loadingCrops = false);
  }

  Future<void> _runOcrOnCrop(int boxId, Uint8List bytes) async {
    try {
      final raw = await _ocrService.processBytesRich(bytes, tag: 'box_$boxId');
      final parsed = _matcher.parse(raw.fullText);
      final result = OcrResult(
        matchedName: null,
        form: parsed.form,
        dosage: parsed.dosage,
        rawText: raw.fullText,
        confidence: 0.0,
        largestText: raw.largestText,
      );
      if (mounted) {
        setState(() {
          _ocrResults[boxId] = result;
          final rowId = _boxToRow[boxId];
          final idx = _rows.indexWhere((r) => r.id == rowId);
          if (idx != -1 && _rows[idx].name.isEmpty) {
            // Only update if the user hasn't already edited this row
            _rows[idx].name   = result.displayName ?? '';
            _rows[idx].form   = result.form ?? '';
            _rows[idx].dosage = result.dosage ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint("OCR error box $boxId: $e");
    }
  }

  // ── Row mutations ─────────────────────────────────────────────────────────

  /// Add an empty row (global "+" at bottom of list)
  void _addEmptyRow() {
    setState(() {
      _rows.add(_MedicineRow(name: '', form: '', dosage: '', count: 1));
    });
  }

  /// Add an empty row AND immediately open the edit sheet.
  /// Used by the footer of "no-name" cards so the user fills details right away.
  Future<void> _addEmptyRowWithEdit() async {
    final newRow = _MedicineRow(name: '', form: '', dosage: '', count: 1);
    setState(() => _rows.add(newRow));

    if (!mounted) return;
    final group = _DisplayGroup(
      key: newRow.groupKey,
      name: '', form: '', dosage: '',
      totalCount: 1,
      rows: [newRow],
    );

    final result = await showModalBottomSheet<_GroupEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupEditSheet(
        group: group,
        titleOverride: "Nouveau médicament",
      ),
    );

    if (!mounted) return;
    setState(() {
      final idx = _rows.indexWhere((r) => r.id == newRow.id);
      if (idx == -1) return;
      if (result == null || result.deleted) {
        _rows.removeAt(idx);
      } else {
        _rows[idx].name   = result.name;
        _rows[idx].form   = result.form;
        _rows[idx].dosage = result.dosage;
        _rows[idx].count  = result.count;
      }
    });
  }

  /// Add a row inheriting the parent's name, decrement parent count by 1,
  /// then immediately open the edit sheet so the user fills form/dosage
  /// (without which the new row would have the same groupKey and re-merge).
  Future<void> _addChildRow(String parentName) async {
    // 1. Decrement first matching parent row
    _MedicineRow? target;
    for (final r in _rows) {
      if (_normName(r.name) == _normName(parentName) && r.count > 0) {
        target = r;
        break;
      }
    }

    // 2. Create the new child row
    final newRow = _MedicineRow(
        name: parentName, form: '', dosage: '', count: 1);

    setState(() {
      if (target != null) target!.count = max(0, target!.count - 1);
      _rows.add(newRow);
    });

    // 3. Immediately open the edit sheet for the new row so the user
    //    can set form/dosage — otherwise it re-merges with the parent.
    if (!mounted) return;
    final group = _DisplayGroup(
      key: newRow.groupKey,
      name: newRow.name,
      form: newRow.form,
      dosage: newRow.dosage,
      totalCount: newRow.count,
      rows: [newRow],
    );

    final result = await showModalBottomSheet<_GroupEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupEditSheet(
        group: group,
        titleOverride: "Nouvelle variante — ${parentName.isEmpty ? 'médicament' : parentName}",
      ),
    );

    if (!mounted) return;
    setState(() {
      final idx = _rows.indexWhere((r) => r.id == newRow.id);
      if (idx == -1) return;
      if (result == null || result.deleted) {
        // User cancelled or deleted → remove new row and restore parent count
        _rows.removeAt(idx);
        if (target != null) {
          final ti = _rows.indexWhere((r) => r.id == target!.id);
          if (ti != -1) _rows[ti].count++;
        }
      } else {
        _rows[idx].name   = result.name;
        _rows[idx].form   = result.form;
        _rows[idx].dosage = result.dosage;
        _rows[idx].count  = result.count;
      }
    });
  }

  String _normName(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Open the edit sheet for a display group. On save, update all its raw rows.
  Future<void> _editGroup(_DisplayGroup g) async {
    final result = await showModalBottomSheet<_GroupEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GroupEditSheet(group: g),
    );
    if (result == null || !mounted) return;

    setState(() {
      if (result.deleted) {
        // Remove all raw rows of this group
        _rows.removeWhere((r) => g.rows.any((gr) => gr.id == r.id));
        return;
      }
      // Apply edits to every raw row in the group
      for (final r in g.rows) {
        final idx = _rows.indexWhere((x) => x.id == r.id);
        if (idx == -1) continue;
        _rows[idx].name   = result.name;
        _rows[idx].form   = result.form;
        _rows[idx].dosage = result.dosage;
      }
      // Apply count: distribute evenly, remainder to first row
      if (g.rows.isNotEmpty) {
        final each = result.count ~/ g.rows.length;
        final rem  = result.count % g.rows.length;
        for (int i = 0; i < g.rows.length; i++) {
          final idx = _rows.indexWhere((x) => x.id == g.rows[i].id);
          if (idx == -1) continue;
          _rows[idx].count = each + (i == 0 ? rem : 0);
        }
      }
    });
  }

  Future<void> _confirmSave() async {
      final zoneCtrl = TextEditingController(text: _shelfName);
      final zoneName = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Zone name"),
          content: TextField(
            controller: zoneCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Zone / shelf name",
              hintText: "e.g. Shelf A, Zone 3…",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, zoneCtrl.text.trim()),
              child: const Text("Confirm"),
            ),
          ],
        ),
      );

      if (zoneName == null || !mounted) return;

      // Build a rich list: one entry per display-group (name+dosage+form+count)
      final groups = _groups;
      final List<Map<String, dynamic>> richMeds = groups
          .where((g) => g.name.trim().isNotEmpty)
          .map((g) => <String, dynamic>{
                'name':   g.name.trim(),
                'dosage': g.dosage.trim(),
                'form':   g.form.trim(),
                'count':  g.totalCount,
              })
          .toList();

      setState(() => _showSuccess = true);
      _successAnim.forward();

      await Future.delayed(const Duration(milliseconds: 2500));
      if (!mounted) return;

      Navigator.pop(context, <String, dynamic>{
        'zoneName': zoneName.isEmpty ? 'Zone' : zoneName,
        'count': _grandTotal,
        'meds': richMeds, // List<Map> with name/dosage/form/count
      });
    }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Column(
                    children: [
                      _buildShelfEditor(),
                      const SizedBox(height: 16),
                      _buildTotalCard(groups),
                      const SizedBox(height: 24),
                      _buildSummaryList(groups),
                      const SizedBox(height: 130),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBottomBar(),
          if (_showSuccess) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(8, 48, 16, 20),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
        ),
        child: Row(children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Expanded(
            child: Text("Résultats du scan",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
          ),
          if (_loadingCrops)
            const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Colors.white70)),
        ]),
      );

  // ── Shelf editor ──────────────────────────────────────────────────────────

  Widget _buildShelfEditor() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Row(children: [
          const Icon(Icons.shelves, color: Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: _isEditingShelf
                ? TextField(
                    controller: _shelfCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                        isDense: true, border: InputBorder.none))
                : Text(_shelfName,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          GestureDetector(
            onTap: () => setState(() {
              if (_isEditingShelf) _shelfName = _shelfCtrl.text;
              _isEditingShelf = !_isEditingShelf;
            }),
            child: Icon(_isEditingShelf ? Icons.check : Icons.edit_outlined,
                size: 20, color: const Color(0xFF64748B)),
          ),
        ]),
      );

  // ── Total card ────────────────────────────────────────────────────────────

  Widget _buildTotalCard(List<_DisplayGroup> groups) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text("Total boîtes",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
              Text("$_grandTotal",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      height: 1.1)),
            ]),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text("${groups.length}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold)),
              const Text("type(s) distincts",
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ],
        ),
      );

  // ── Summary list ──────────────────────────────────────────────────────────

  Widget _buildSummaryList(List<_DisplayGroup> groups) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Text("Résumé par médicament",
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Spacer(),
          // Hint text
          const Text("Tap pour modifier",
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
        ]),
        const SizedBox(height: 12),

        // One card per display group
        ...groups.map((g) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildGroupCard(g),
            )),

        // ── "Add empty" card ──────────────────────────────────────────────
        _buildAddEmptyCard(),
      ],
    );
  }

  // ── Group card ────────────────────────────────────────────────────────────

  Widget _buildGroupCard(_DisplayGroup g) {
    final color = _colorForKey(g.key);
    final bool noName   = g.name.trim().isEmpty;
    final bool noForm   = g.form.trim().isEmpty;
    final bool noDosage = g.dosage.trim().isEmpty;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: Column(
            children: [
              // ── Main row: info + count stepper ─────────────────────
              InkWell(
                onTap: () => _editGroup(g),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                  child: Row(
                    children: [
                      // ── Left block ──────────────────────────────────
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                child: Text(
                                  noName ? "— Nom inconnu —" : g.name,
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: noName
                                          ? Colors.grey
                                          : const Color(0xFF1E293B),
                                      fontStyle: noName
                                          ? FontStyle.italic
                                          : FontStyle.normal),
                                ),
                              ),
                              const Icon(Icons.edit_outlined,
                                  size: 14, color: Color(0xFFCBD5E1)),
                            ]),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              _chip(Icons.category_outlined,
                                  noForm ? "Forme ?" : g.form,
                                  const Color(0xFF0EA5E9),
                                  faded: noForm),
                              _chip(Icons.science_outlined,
                                  noDosage ? "Dosage ?" : g.dosage,
                                  const Color(0xFFF59E0B),
                                  faded: noDosage),
                            ]),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildStepper(g, color),
                    ],
                  ),
                ),
              ),

              // ── Footer: "Ajouter variante" ──────────────────────────
              const Divider(height: 1, thickness: 0.5, indent: 14),
              InkWell(
                onTap: () {
                  if (noName) {
                    _addEmptyRowWithEdit();
                  } else {
                    _addChildRow(g.name);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Row(children: [
                    Icon(Icons.add_circle_outline, size: 15, color: color),
                    const SizedBox(width: 6),
                    Text(
                      noName
                          ? "Ajouter une ligne vide"
                          : "Ajouter variante (${g.name})",
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color,
      {bool faded = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: faded
              ? Colors.grey.withOpacity(0.08)
              : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 10, color: faded ? Colors.grey : color),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: faded ? Colors.grey : color,
                  fontStyle:
                      faded ? FontStyle.italic : FontStyle.normal)),
        ]),
      );

  Widget _buildStepper(_DisplayGroup g, Color color) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Count badge
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
              "${g.totalCount}",
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color),
            ),
          ),
          const SizedBox(height: 5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _stepBtn(Icons.remove_rounded, color, () {
              setState(() {
                // Decrement: subtract from first row with count > 0
                for (final r in g.rows) {
                  final idx = _rows.indexWhere((x) => x.id == r.id);
                  if (idx != -1 && _rows[idx].count > 0) {
                    _rows[idx].count--;
                    break;
                  }
                }
              });
            }),
            const SizedBox(width: 4),
            _stepBtn(Icons.add_rounded, color, () {
              setState(() {
                // Increment: add to first row
                if (g.rows.isNotEmpty) {
                  final idx = _rows.indexWhere((x) => x.id == g.rows.first.id);
                  if (idx != -1) _rows[idx].count++;
                }
              });
            }),
          ]),
        ],
      );

  Widget _stepBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7)),
          child: Icon(icon, size: 15, color: color),
        ),
      );

  // ── "Add empty" last card ─────────────────────────────────────────────────

  Widget _buildAddEmptyCard() => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: _addEmptyRow,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 1.5),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      color: Color(0xFF64748B), size: 20),
                  SizedBox(width: 8),
                  Text("Ajouter un médicament manuellement",
                      style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      );

  // ── Bottom bar ────────────────────────────────────────────────────────────

  Widget _buildBottomBar() => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              onPressed: _confirmSave,
              child: Text(
                "Confirmer  ·  $_grandTotal boîte${_grandTotal != 1 ? 's' : ''}",
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Retour à l'éditeur",
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ),
          ]),
        ),
      );

  // ── Success overlay ───────────────────────────────────────────────────────

  Widget _buildSuccessOverlay() => Positioned.fill(
        child: Container(
          color: Colors.black54,
          child: Center(
            child: SlideTransition(
              position: _slideAnim,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                    vertical: 30, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF059669), Color(0xFF10B981)]),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 80, color: Colors.white),
                      SizedBox(height: 16),
                      Text("SCAN CONFIRMÉ",
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
// Group edit bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _GroupEditResult {
  final String name;
  final String form;
  final String dosage;
  final int count;
  final bool deleted;
  const _GroupEditResult({
    required this.name,
    required this.form,
    required this.dosage,
    required this.count,
    this.deleted = false,
  });
}

class _GroupEditSheet extends StatefulWidget {
  final _DisplayGroup group;
  final String? titleOverride;
  const _GroupEditSheet({required this.group, this.titleOverride});

  @override
  State<_GroupEditSheet> createState() => _GroupEditSheetState();
}

class _GroupEditSheetState extends State<_GroupEditSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _formCtrl;
  late final TextEditingController _dosageCtrl;
  late int _count;

  @override
  void initState() {
    super.initState();
    _nameCtrl   = TextEditingController(text: widget.group.name);
    _formCtrl   = TextEditingController(text: widget.group.form);
    _dosageCtrl = TextEditingController(text: widget.group.dosage);
    _count      = widget.group.totalCount;
    // Rebuild clear buttons when text changes
    _nameCtrl.addListener(() => setState(() {}));
    _formCtrl.addListener(() => setState(() {}));
    _dosageCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _formCtrl.dispose();
    _dosageCtrl.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(
        context,
        _GroupEditResult(
          name: _nameCtrl.text.trim(),
          form: _formCtrl.text.trim(),
          dosage: _dosageCtrl.text.trim(),
          count: _count,
        ),
      );

  void _delete() => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Supprimer cette ligne ?"),
          content: Text(
              "\"${_nameCtrl.text.isEmpty ? 'Nom inconnu' : _nameCtrl.text}\" "
              "sera retiré du résumé."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annuler")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600),
              onPressed: () {
                Navigator.pop(context); // close dialog
                Navigator.pop(
                    context,
                    const _GroupEditResult(
                        name: '', form: '', dosage: '', count: 0,
                        deleted: true));
              },
              child: const Text("Supprimer",
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Push sheet above keyboard
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F172A),
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.zero,
            children: [
              // ── Handle ────────────────────────────────────────────────
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 6),
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // ── Title row ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 10, 14),
                child: Row(children: [
                  Expanded(
                    child: Text(
                        widget.titleOverride ?? "Modifier le médicament",
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 20),
                    tooltip: "Supprimer cette ligne",
                    onPressed: _delete,
                  ),
                  TextButton(
                    onPressed: _save,
                    child: const Text("Enregistrer",
                        style: TextStyle(
                            color: Color(0xFF14B8A6),
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ),
                ]),
              ),

              const Divider(height: 1, color: Color(0xFF1E293B)),
              const SizedBox(height: 14),

              // ── Edit fields ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [
                  _field(
                    ctrl: _nameCtrl,
                    label: "Nom du médicament",
                    icon: Icons.medication_outlined,
                    color: const Color(0xFF6366F1),
                    hint: "ex: Doliprane",
                  ),
                  const SizedBox(height: 10),
                  _field(
                    ctrl: _formCtrl,
                    label: "Forme pharmaceutique",
                    icon: Icons.category_outlined,
                    color: const Color(0xFF0EA5E9),
                    hint: "ex: Comprimé, Sirop, Injectable…",
                  ),
                  const SizedBox(height: 10),
                  _field(
                    ctrl: _dosageCtrl,
                    label: "Dosage",
                    icon: Icons.science_outlined,
                    color: const Color(0xFFF59E0B),
                    hint: "ex: 500 MG, 1 G / 5 ML…",
                  ),
                ]),
              ),

              const SizedBox(height: 20),
              const Divider(height: 1, color: Color(0xFF1E293B)),
              const SizedBox(height: 16),

              // ── Count adjuster ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Nombre de boîtes",
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _countBtn(Icons.remove_rounded, Colors.redAccent,
                            () => setState(
                                () => _count = max(0, _count - 1))),
                        const SizedBox(width: 28),
                        Text("$_count",
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 28),
                        _countBtn(Icons.add_rounded,
                            const Color(0xFF14B8A6),
                            () => setState(() => _count++)),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    required Color color,
    required String hint,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: label,
                labelStyle:
                    TextStyle(color: color.withOpacity(0.8), fontSize: 11),
                hintText: hint,
                hintStyle: const TextStyle(
                    color: Color(0xFF475569), fontSize: 12),
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (ctrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => ctrl.clear(),
              child: const Icon(Icons.close_rounded,
                  size: 16, color: Color(0xFF64748B)),
            ),
        ]),
      );

  Widget _countBtn(IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
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