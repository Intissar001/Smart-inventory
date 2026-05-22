import 'dart:async';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:camera/camera.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:io';

// ─────────────────────────────────────────────
// Data Model
// ─────────────────────────────────────────────
class DetectedBox {
  final int id;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String label;
  final double confidence;

  DetectedBox({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.label,
    required this.confidence,
  });

  double get width => x2 - x1;
  double get height => y2 - y1;
}

// ─────────────────────────────────────────────
// Camera Scan Screen
// ─────────────────────────────────────────────
class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  Future<void>? _initializeControllerFuture;

  List<DetectedBox> _detectedBoxes = [];
  bool _isScanning = false;
  bool _flashEnabled = false;
  int _detectionCount = 0;
  String _imageQuality = 'good';
  String _lightingLevel = 'optimal';
  bool _isSending = false;

  // Dimensions de l'image
  double _imageWidth = 736.0;
  double _imageHeight = 920.0;

  late AnimationController _pulseController;

  // IP de votre PC (téléphone physique)
  static const String _backendUrl = "http://192.168.1.3:8000/detect";

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _initCamera();
    setState(() => _isScanning = true);
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

  // ✅ MODIFIÉ: accepte l'image UI
  Future<void> _sendImageToBackend(File imageFile, ui.Image uiImage) async {
    setState(() => _isSending = true);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(_backendUrl),
      );

      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode != 200) {
        debugPrint("Backend error ${response.statusCode}: $responseBody");
        _showError("Erreur backend: ${response.statusCode}");
        return;
      }

      final json = jsonDecode(responseBody);
      final List<dynamic> detections = json['detections'] ?? [];

      // Récupérer les dimensions de l'image depuis le backend
      if (json['image_width'] != null) {
        _imageWidth = (json['image_width'] as num).toDouble();
      }
      if (json['image_height'] != null) {
        _imageHeight = (json['image_height'] as num).toDouble();
      }

      final List<DetectedBox> boxes = detections.asMap().entries.map((entry) {
        final i = entry.key;
        final item = entry.value;
        final bbox = item['bbox'] as List<dynamic>;

        return DetectedBox(
          id: i,
          x1: (bbox[0] as num).toDouble(),
          y1: (bbox[1] as num).toDouble(),
          x2: (bbox[2] as num).toDouble(),
          y2: (bbox[3] as num).toDouble(),
          label: item['label'] ?? 'Object',
          confidence: (item['confidence'] as num).toDouble(),
        );
      }).toList();

      // ✅ Naviguer avec l'image et les boxes
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ScanResultsScreen(
              detectedBoxes: boxes,
              totalCount: boxes.length,
              imageQuality: _imageQuality,
              lightingLevel: _lightingLevel,
              capturedImage: uiImage,  // ✅ L'image capturée !
              imageWidth: _imageWidth,   // ✅ Dimensions originales
              imageHeight: _imageHeight,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("API call failed: $e");
      _showError("Impossible de contacter le backend.\nVérifie l'IP et que le serveur tourne.");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ✅ MODIFIÉ: capture et conversion de l'image
  void _handleCapture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isSending) return;

    try {
      await _controller!.setFlashMode(
        _flashEnabled ? FlashMode.torch : FlashMode.off,
      );

      final XFile imageFile = await _controller!.takePicture();
      final File file = File(imageFile.path);

      // ✅ Convertir en ui.Image pour l'affichage
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final uiImage = frame.image;

      await _sendImageToBackend(file, uiImage);
    } catch (e) {
      debugPrint("Capture error: $e");
      _showError("Erreur lors de la capture: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        child: Stack(
          children: [
            _buildCameraBackground(),
            _buildGridOverlay(),
            _buildCenterFocusIndicator(),
            _buildHeader(),
            _buildQualityIndicators(),
            _buildCaptureButton(),
            if (_isSending) _buildLoadingOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.6),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF14B8A6)),
              SizedBox(height: 16),
              Text(
                "Analyse YOLO en cours...",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraBackground() {
    return FutureBuilder<void>(
      future: _initializeControllerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            _controller != null) {
          return SizedBox.expand(child: CameraPreview(_controller!));
        } else {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        }
      },
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
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: _buildBoxCorners(),
        ),
      ),
    );
  }

  Widget _buildBoxCorners() {
    const side = 16.0;
    const border = BorderSide(color: Color(0xFF14B8A6), width: 4);
    return Stack(
      children: [
        Positioned(
          top: -1,
          left: -1,
          child: Container(
            width: side,
            height: side,
            decoration: const BoxDecoration(
              border: Border(top: border, left: border),
            ),
          ),
        ),
        Positioned(
          top: -1,
          right: -1,
          child: Container(
            width: side,
            height: side,
            decoration: const BoxDecoration(
              border: Border(top: border, right: border),
            ),
          ),
        ),
        Positioned(
          bottom: -1,
          left: -1,
          child: Container(
            width: side,
            height: side,
            decoration: const BoxDecoration(
              border: Border(bottom: border, left: border),
            ),
          ),
        ),
        Positioned(
          bottom: -1,
          right: -1,
          child: Container(
            width: side,
            height: side,
            decoration: const BoxDecoration(
              border: Border(bottom: border, right: border),
            ),
          ),
        ),
      ],
    );
  }

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
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildIconButton(Icons.arrow_back, () => Navigator.pop(context)),
            _buildIconButton(
              _flashEnabled ? Icons.flash_on : Icons.flash_off,
              () => setState(() => _flashEnabled = !_flashEnabled),
              color: _flashEnabled
                  ? const Color(0xFFFBBF24)
                  : Colors.white,
              bgColor: _flashEnabled
                  ? const Color(0xFFFBBF24).withOpacity(0.3)
                  : Colors.white.withOpacity(0.1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    VoidCallback onTap, {
    Color color = Colors.white,
    Color? bgColor,
  }) {
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

  Widget _buildQualityIndicators() {
    return Positioned(
      top: 180,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildInfoChip(
            "IMAGE QUALITY",
            _imageQuality,
            _imageQuality == 'excellent' ? Colors.green : Colors.yellow,
          ),
          _buildInfoChip(
            "LIGHTING",
            _lightingLevel,
            _lightingLevel == 'optimal' ? Colors.green : Colors.yellow,
          ),
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
          Icon(
            statusColor == Colors.green
                ? Icons.check_circle
                : Icons.warning,
            color: statusColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value.toUpperCase(),
                style: TextStyle(
                  color: statusColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
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
            builder: (context, child) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: _isSending
                        ? [Colors.grey.shade700, Colors.grey.shade600]
                        : [const Color(0xFF2563EB), const Color(0xFF0D9488)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withOpacity(
                        _isSending
                            ? 0.1
                            : 0.5 + _pulseController.value * 0.3,
                      ),
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
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isSending ? "Envoi en cours..." : "Capture Scan",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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

// ─────────────────────────────────────────────
// Scan Results Screen (avec bounding boxes)
// ─────────────────────────────────────────────
class ScanResultsScreen extends StatefulWidget {
  final List<DetectedBox> detectedBoxes;
  final int totalCount;
  final String imageQuality;
  final String lightingLevel;
  final ui.Image? capturedImage;
  final double imageWidth;
  final double imageHeight;

  const ScanResultsScreen({
    super.key,
    required this.detectedBoxes,
    required this.totalCount,
    required this.imageQuality,
    required this.lightingLevel,
    this.capturedImage,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  State<ScanResultsScreen> createState() => _ScanResultsScreenState();
}

class _ScanResultsScreenState extends State<ScanResultsScreen>
    with TickerProviderStateMixin {
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
    ).animate(
      CurvedAnimation(
        parent: _successAnimController,
        curve: Curves.elasticOut,
      ),
    );
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
    Future.delayed(
      const Duration(milliseconds: 2500),
      () => Navigator.pop(context),
    );
  }

  // ✅ NOUVEAU: Fonction pour dessiner les bounding boxes
  Widget _buildBox(DetectedBox box, double containerWidth, double containerHeight) {
    // Scaling des coordonnées
    final scaleX = containerWidth / widget.imageWidth;
    final scaleY = containerHeight / widget.imageHeight;

    double left = box.x1 * scaleX;
    double top = box.y1 * scaleY;
    double width = box.width * scaleX;
    double height = box.height * scaleY;

    // ✅ Correction des valeurs négatives ou trop petites
    left = left.clamp(0.0, containerWidth - 5);
    top = top.clamp(0.0, containerHeight - 5);
    width = width.clamp(5.0, containerWidth - left);
    height = height.clamp(5.0, containerHeight - top);

    if (width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF14B8A6), width: 2.5),
          borderRadius: BorderRadius.circular(4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14B8A6).withOpacity(0.5),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        // ✅ Badge à l'intérieur sans margin négative
        child: ClipRect(
          child: Stack(
            children: [
              // Badge collé en haut à gauche
              Positioned(
                left: 0,
                top: 0,
                child: Transform.translate(
                  offset: const Offset(0, -24),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF14B8A6), Color(0xFF0D9488)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          box.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "${(box.confidence * 100).round()}%",
                          style: const TextStyle(
                            color: Color(0xFFFDE047),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
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
      ),
    );
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
                      _buildImagePreview(),  // ✅ Image avec bounding boxes
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

  // ✅ MODIFIÉ: Image preview avec bounding boxes
  Widget _buildImagePreview() {
    return Container(
      height: 260,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: const Color(0xFF1E293B),
      ),
      child: widget.capturedImage != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RawImage(
                      image: widget.capturedImage,
                      fit: BoxFit.cover,
                    ),
                  ),
                  // ✅ Affichage des bounding boxes avec LayoutBuilder
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: widget.detectedBoxes.map((box) {
                          return _buildBox(box, constraints.maxWidth, 260.0);
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            )
          : const Center(
              child: Icon(Icons.image, color: Colors.white24, size: 50),
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
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 80, color: Colors.white),
                  SizedBox(height: 20),
                  Text(
                    "SCAN CONFIRMED",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0D9488)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          const Text(
            "Scan Results",
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        children: [
          const Icon(Icons.shelves, color: Color(0xFF2563EB)),
          const SizedBox(width: 16),
          Expanded(
            child: _isEditingShelf
                ? TextField(
                    controller: _shelfController,
                    decoration: const InputDecoration(isDense: true),
                  )
                : Text(
                    _shelfName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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

  Widget _buildTotalCountCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF0D9488)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          const Text(
            "Total Boxes Detected",
            style: TextStyle(color: Colors.white70),
          ),
          Text(
            "$_boxCount",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 64,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdjustmentControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildCircleButton(
          Icons.remove,
          Colors.red,
          () => setState(() => _boxCount = max(0, _boxCount - 1)),
        ),
        const SizedBox(width: 24),
        Text(
          "$_boxCount",
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
        ),
        const SizedBox(width: 24),
        _buildCircleButton(
          Icons.add,
          Colors.green,
          () => setState(() => _boxCount++),
        ),
      ],
    );
  }

  Widget _buildCircleButton(
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }

  Widget _buildFixedBottomButtons() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: _confirmAndSave,
              child: const Text(
                "Confirm Result",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "Rescan",
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Grid Painter
// ─────────────────────────────────────────────
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.15)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}