import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:math';

// Data M
class DetectedBox {
  final int id;
  final double x;
  final double y;
  final double width;
  final double height;
  final String label;
  final double confidence;

  DetectedBox({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.label,
    required this.confidence,
  });
}

// camera screen!
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> with TickerProviderStateMixin {
  List<DetectedBox> _detectedBoxes = [];
  bool _isScanning = false;
  bool _flashEnabled = false;
  int _detectionCount = 0;
  String _imageQuality = 'good';
  String _lightingLevel = 'optimal';
  late List<Timer> _timers;
  final Random _random = Random();
  late AnimationController _pulseController;

  ui.Image? _capturedImage;
  bool _showCropper = false;

  @override
  void initState() {
    super.initState();
    _timers = [];
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _startScanning();
  }

  @override
  void dispose() {
    for (var timer in _timers) {
      timer.cancel();
    }
    _pulseController.dispose();
    super.dispose();
  }

  void _startScanning() {
    setState(() => _isScanning = true);

    final List<DetectedBox> allBoxes = _generateMockData();
    for (int i = 0; i < allBoxes.length; i++) {
      final timer = Timer(Duration(milliseconds: 200 + i * 150), () {
        if (mounted) {
          setState(() {
            _detectedBoxes.add(allBoxes[i]);
            _detectionCount++;
          });
        }
      });
      _timers.add(timer);
    }

    _timers.add(Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      if (mounted) {
        setState(() {
          int change = _random.nextInt(5) - 2;
          _detectionCount = (_detectionCount + change).clamp(30, 45);
        });
      }
    }));

    _timers.add(Timer.periodic(const Duration(milliseconds: 3000), (timer) {
      if (mounted) {
        setState(() {
          final qualities = ['excellent', 'good', 'good', 'excellent'];
          final lighting = ['optimal', 'optimal', 'low', 'optimal'];
          _imageQuality = qualities[_random.nextInt(qualities.length)];
          _lightingLevel = lighting[_random.nextInt(lighting.length)];
        });
      }
    }));
  }

  List<DetectedBox> _generateMockData() {
    return [
      DetectedBox(id: 1, x: 8, y: 15, width: 18, height: 14, label: "Box", confidence: 0.98),
      DetectedBox(id: 2, x: 28, y: 17, width: 16, height: 12, label: "Box", confidence: 0.96),
      DetectedBox(id: 3, x: 48, y: 16, width: 17, height: 13, label: "Box", confidence: 0.97),
      DetectedBox(id: 4, x: 68, y: 18, width: 19, height: 14, label: "Box", confidence: 0.95),
      DetectedBox(id: 5, x: 12, y: 33, width: 16, height: 13, label: "Box", confidence: 0.94),
      DetectedBox(id: 6, x: 32, y: 35, width: 18, height: 12, label: "Box", confidence: 0.98),
      DetectedBox(id: 7, x: 52, y: 34, width: 17, height: 13, label: "Box", confidence: 0.96),
      DetectedBox(id: 8, x: 72, y: 36, width: 16, height: 12, label: "Box", confidence: 0.97),
      DetectedBox(id: 9, x: 10, y: 51, width: 19, height: 14, label: "Box", confidence: 0.95),
      DetectedBox(id: 10, x: 30, y: 53, width: 17, height: 13, label: "Box", confidence: 0.94),
      DetectedBox(id: 11, x: 50, y: 52, width: 18, height: 12, label: "Box", confidence: 0.98),
      DetectedBox(id: 12, x: 70, y: 54, width: 16, height: 13, label: "Box", confidence: 0.96),
      DetectedBox(id: 13, x: 15, y: 69, width: 17, height: 12, label: "Box", confidence: 0.97),
      DetectedBox(id: 14, x: 35, y: 71, width: 18, height: 13, label: "Box", confidence: 0.95),
      DetectedBox(id: 15, x: 55, y: 70, width: 16, height: 12, label: "Box", confidence: 0.94),
      DetectedBox(id: 16, x: 75, y: 72, width: 17, height: 13, label: "Box", confidence: 0.98),
    ];
  }

  void _handleCapture() async {
    if (!_isScanning) return;
    setState(() => _isScanning = false);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bgPaint = Paint()..color = const Color(0xFF1E293B);
    canvas.drawRect(Rect.fromLTWH(0, 0, 1080, 1920), bgPaint);

    _drawSimulatedShelf(canvas);
    _drawBoxesOnCanvas(canvas);

    final picture = recorder.endRecording();
    final capturedImg = await picture.toImage(1080, 1920);

    setState(() {
      _capturedImage = capturedImg;
      _showCropper = true;
    });
  }

  void _drawSimulatedShelf(Canvas canvas) {
    final shelfPaint = Paint()..color = const Color(0xFF78350F).withOpacity(0.3);
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(Rect.fromLTWH(100 + i * 300, 300, 200, 150), shelfPaint);
      canvas.drawRect(Rect.fromLTWH(100 + i * 300, 700, 200, 150), shelfPaint);
      canvas.drawRect(Rect.fromLTWH(100 + i * 300, 1100, 200, 150), shelfPaint);
    }
  }

  void _drawBoxesOnCanvas(Canvas canvas) {
    for (var box in _detectedBoxes.take(10)) {
      final boxPaint = Paint()
        ..color = const Color(0xFF14B8A6).withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;

      canvas.drawRect(
        Rect.fromLTWH(
          box.x / 100 * 1080, box.y / 100 * 1920,
          box.width / 100 * 1080, box.height / 100 * 1920,
        ),
        boxPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: "${(box.confidence * 100).round()}%",
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(canvas, Offset(box.x / 100 * 1080 + 10, box.y / 100 * 1920 - 25));
    }
  }

  void _onCropComplete(ui.Image croppedImage) {
    setState(() {
      _capturedImage = croppedImage;
      _showCropper = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScanResultsScreen(
          detectedBoxes: _detectedBoxes,
          totalCount: _detectionCount,
          imageQuality: _imageQuality,
          lightingLevel: _lightingLevel,
          capturedImage: _capturedImage,
        ),
      ),
    );
  }

  void _cancelCrop() {
    setState(() {
      _showCropper = false;
      _capturedImage = null;
      _isScanning = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    if (_showCropper && _capturedImage != null) {
      return ImageCropperScreen(
        capturedImage: _capturedImage!,
        onCropComplete: _onCropComplete,
        onCancel: _cancelCrop,
      );
    }

    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            _buildCameraBackground(),
            ..._detectedBoxes.map((box) => _buildDetectionBox(box, size)),
            _buildGridOverlay(),
            _buildCenterFocusIndicator(),
            _buildHeader(),
            _buildCounterDisplay(),
            _buildQualityIndicators(),
            _buildCaptureButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBackground() {
    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF334155), Color(0xFF475569), Color(0xFF1E293B)],
            ),
          ),
        ),
        AnimatedOpacity(
          opacity: _flashEnabled ? 0.3 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            color: Colors.white,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ],
    );
  }

  Widget _buildDetectionBox(DetectedBox box, Size size) {
    final left = box.x / 100 * size.width;
    final top = box.y / 100 * size.height;
    final width = box.width / 100 * size.width;
    final height = box.height / 100 * size.height;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF14B8A6), width: 2),
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Color(0xFF14B8A6), blurRadius: 30, spreadRadius: 2)],
        ),
        child: Stack(
          children: [
            _buildConfidenceBadge(box),
            _buildBoxCorners(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfidenceBadge(DetectedBox box) {
    return Positioned(
      top: -28,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4ADE80), Color(0xFF14B8A6)]),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Text(
            "${(box.confidence * 100).round()}%",
            style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget _buildBoxCorners() {
    const side = 16.0;
    const border = BorderSide(color: Color(0xFF14B8A6), width: 4);
    return Stack(
      children: [
        Positioned(top: -1, left: -1, child: Container(width: side, height: side, decoration: const BoxDecoration(border: Border(top: border, left: border)))),
        Positioned(top: -1, right: -1, child: Container(width: side, height: side, decoration: const BoxDecoration(border: Border(top: border, right: border)))),
        Positioned(bottom: -1, left: -1, child: Container(width: side, height: side, decoration: const BoxDecoration(border: Border(bottom: border, left: border)))),
        Positioned(bottom: -1, right: -1, child: Container(width: side, height: side, decoration: const BoxDecoration(border: Border(bottom: border, right: border)))),
      ],
    );
  }

  Widget _buildGridOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(painter: GridPainter()),
      ),
    );
  }

  Widget _buildCenterFocusIndicator() {
    return Center(
      child: IgnorePointer(
        child: Container(
          width: 256,
          height: 256,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _buildBoxCorners(),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Positioned(
      top: 0, left: 0, right: 0,
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
            _buildIconButton(Icons.arrow_back, () => Navigator.pop(context)),
            _buildIconButton(
              _flashEnabled ? Icons.flash_on : Icons.flash_off,
                  () => setState(() => _flashEnabled = !_flashEnabled),
              color: _flashEnabled ? const Color(0xFFFBBF24) : Colors.white,
              bgColor: _flashEnabled ? const Color(0xFFFBBF24).withOpacity(0.3) : Colors.white.withOpacity(0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap, {Color color = Colors.white, Color? bgColor}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor ?? Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }

  Widget _buildCounterDisplay() {
    return Positioned(
      top: 100, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xFF3B82F6), blurRadius: 20)],
          ),
          child: RichText(
            text: TextSpan(
              children: [
                const TextSpan(text: "Boxes Detected: ", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                TextSpan(text: "$_detectionCount", style: const TextStyle(color: Color(0xFFFDE047), fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQualityIndicators() {
    return Positioned(
      top: 180, left: 16, right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoChip("IMAGE QUALITY", _imageQuality, _imageQuality == 'excellent' ? Colors.green : Colors.yellow),
          _buildInfoChip("LIGHTING", _lightingLevel, _lightingLevel == 'optimal' ? Colors.green : Colors.yellow),
        ],
      ),
    );
  }

  Widget _buildInfoChip(String label, String value, Color statusColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(statusColor == Colors.green ? Icons.check_circle : Icons.warning, color: statusColor, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, letterSpacing: 1)),
              Text(value.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter, end: Alignment.topCenter,
            colors: [Colors.black.withOpacity(0.9), Colors.black.withOpacity(0.7), Colors.transparent],
          ),
        ),
        child: GestureDetector(
          onTap: _handleCapture,
          child: AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0D9488)]),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(0.5 + _pulseController.value * 0.3),
                      blurRadius: 30, spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, color: Colors.white, size: 32),
                    SizedBox(width: 12),
                    Text("Capture Scan", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}


// Cropping img

class ImageCropperScreen extends StatefulWidget {
  final ui.Image capturedImage;
  final Function(ui.Image) onCropComplete;
  final VoidCallback onCancel;

  const ImageCropperScreen({
    super.key,
    required this.capturedImage,
    required this.onCropComplete,
    required this.onCancel,
  });

  @override
  State<ImageCropperScreen> createState() => _ImageCropperScreenState();
}

class _ImageCropperScreenState extends State<ImageCropperScreen> {
  double scale = 1.0;
  Offset offset = Offset.zero;
  late Rect cropRect;
  late Size imageSize;
  Uint8List? imageBytes;

  @override
  void initState() {
    super.initState();
    imageSize = Size(widget.capturedImage.width.toDouble(), widget.capturedImage.height.toDouble());
    cropRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
    _loadImageBytes();
  }

  Future<void> _loadImageBytes() async {
    final byteData = await widget.capturedImage.toByteData(format: ui.ImageByteFormat.png);
    if (mounted) setState(() => imageBytes = byteData!.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _buildAppBar(),
      body: imageBytes == null ? const Center(child: CircularProgressIndicator()) : _buildCropBody(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: widget.onCancel),
      title: const Text("Crop Image", style: TextStyle(color: Colors.white)),
      actions: [
        TextButton(
          onPressed: _processCrop,
          child: const Text("Done", style: TextStyle(color: Colors.green, fontSize: 16)),
        ),
      ],
    );
  }

  Future<void> _processCrop() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(widget.capturedImage, cropRect, Rect.fromLTWH(0, 0, cropRect.width, cropRect.height), Paint());
    final picture = recorder.endRecording();
    final croppedImage = await picture.toImage(cropRect.width.toInt(), cropRect.height.toInt());
    widget.onCropComplete(croppedImage);
  }

  Widget _buildCropBody() {
    return LayoutBuilder(builder: (context, constraints) {
      return Stack(
        children: [
          Center(
            child: GestureDetector(
              onScaleUpdate: (details) {
                setState(() {
                  scale = (scale * details.scale).clamp(1.0, 3.0);
                  offset += details.focalPointDelta;
                });
              },
              child: Transform(
                transform: Matrix4.identity()..translate(offset.dx, offset.dy)..scale(scale),
                child: Image.memory(imageBytes!, width: imageSize.width, height: imageSize.height, fit: BoxFit.cover),
              ),
            ),
          ),
          _buildOverlayArea(constraints),
          _buildCropControls(),
        ],
      );
    });
  }

  Widget _buildOverlayArea(BoxConstraints constraints) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.5),
        child: Center(
          child: Container(
            width: constraints.maxWidth * 0.9,
            height: constraints.maxHeight * 0.7,
            decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildCropControls() {
    return Positioned(
      bottom: 40, left: 20, right: 20,
      child: Column(
        children: [
          Text("Drag and pinch to adjust crop area", style: TextStyle(color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 16),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return GestureDetector(
      onTap: () => setState(() {
        scale = 1.0;
        offset = Offset.zero;
        cropRect = Rect.fromLTWH(0, 0, imageSize.width, imageSize.height);
      }),
      child: Column(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle), child: const Icon(Icons.crop_free, color: Colors.white)),
          const SizedBox(height: 8),
          const Text("Reset", style: TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}

// Result!

class ScanResultsScreen extends StatefulWidget {
  final List<DetectedBox> detectedBoxes;
  final int totalCount;
  final String imageQuality;
  final String lightingLevel;
  final ui.Image? capturedImage;

  const ScanResultsScreen({
    super.key,
    required this.detectedBoxes,
    required this.totalCount,
    required this.imageQuality,
    required this.lightingLevel,
    this.capturedImage,
  });

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen> with TickerProviderStateMixin {
  late int _boxCount;

  String _shelfName = "Shelf A";
  bool _isEditingShelf = false;
  final TextEditingController _shelfController = TextEditingController();

  late AnimationController _successAnimController;
  late Animation<Offset> _slideAnimation;
  bool _showSuccessOverlay = false;

  @override
  void initState() {
    super.initState();
    _boxCount = widget.totalCount;
    _shelfController.text = _shelfName;

    _successAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _successAnimController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _shelfController.dispose();
    _successAnimController.dispose();
    super.dispose();
  }

  void _confirmAndSave() {
    setState(() => _showSuccessOverlay = true);
    _successAnimController.forward();

    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      _buildImagePreview(),
                      const SizedBox(height: 24),
                      _buildTotalCountCard(),
                      const SizedBox(height: 24),
                      _buildAdjustmentControls(),
                      const SizedBox(height: 140),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildFixedBottomButtons(),
          if (_showSuccessOverlay) _buildSuccessOverlay(),
        ],
      ),
    );
  }

  Widget _buildSuccessOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black54,
        child: Center(
          child: SlideTransition(
            position: _slideAnimation,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF059669), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_rounded, size: 50, color: Color(0xFF059669)),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "SCAN CONFIRMED",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Data saved successfully",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0D9488)])),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back, color: Colors.white)),
          const Text("Scan Results", style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildShelfEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)]),
      child: Row(
        children: [
          const Icon(Icons.shelves, color: Color(0xFF2563EB)),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditingShelf
                ? TextField(controller: _shelfController, decoration: const InputDecoration(isDense: true))
                : Text(_shelfName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: Icon(_isEditingShelf ? Icons.check : Icons.edit),
            onPressed: () => setState(() {
              if (_isEditingShelf) _shelfName = _shelfController.text;
              _isEditingShelf = !_isEditingShelf;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview() {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24), color: const Color(0xFF1E293B)),
      child: const Center(child: Icon(Icons.image, color: Colors.white24, size: 50)),
    );
  }

  Widget _buildTotalCountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2563EB), Color(0xFF0D9488)]), borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          const Text("Total Boxes Detected", style: TextStyle(color: Colors.white70)),
          Text("$_boxCount", style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAdjustmentControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleButton(Icons.remove, Colors.red, () => setState(() => _boxCount = max(0, _boxCount - 1))),
        const SizedBox(width: 24),
        Text("$_boxCount", style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold)),
        const SizedBox(width: 24),
        _buildCircleButton(Icons.add, Colors.green, () => setState(() => _boxCount++)),
      ],
    );
  }

  Widget _buildCircleButton(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(width: 64, height: 64, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)), child: Icon(icon, color: Colors.white)),
    );
  }

  Widget _buildFixedBottomButtons() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: Container(
        padding: const EdgeInsets.all(20),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: const Color(0xFF2563EB),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: _confirmAndSave,
              child: const Text("Confirm Result", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Rescan", style: TextStyle(color: Colors.grey))),
          ],
        ),
      ),
    );
  }
}


class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withOpacity(0.15)..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 40) { canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint); }
    for (double y = 0; y < size.height; y += 40) { canvas.drawLine(Offset(0, y), Offset(size.width, y), paint); }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}