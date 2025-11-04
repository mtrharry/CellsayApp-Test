import 'dart:async';
import 'dart:typed_data';
import 'dart:ui'; // ✅ requerido para WriteBuffer

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/document_scan_result.dart';
import '../../services/document_scanner_service.dart';
import '../widgets/document_preview.dart';

/// Pantalla para escanear documentos y leer texto con OCR + TTS
class DocumentScannerScreen extends StatefulWidget {
  const DocumentScannerScreen({super.key});

  @override
  State<DocumentScannerScreen> createState() => _DocumentScannerScreenState();
}

class _DocumentScannerScreenState extends State<DocumentScannerScreen> {
  final _scannerService = DocumentScannerService();
  final _tts = FlutterTts();

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String? _cameraError;

  XFile? _capturedFile;
  DocumentScanResult? _result;

  bool _isScanningDocument = false;
  bool _isProcessingFrame = false;
  bool _isCapturingDocument = false;
  bool _isSpeaking = false;
  bool _cancelSpeaking = false;

  @override
  void initState() {
    super.initState();
    _configureTts();
    _initCamera();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('es-MX');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _initCamera() async {
    CameraController? controller;

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() => _cameraError = 'Se requiere el permiso de cámara para escanear documentos.');
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _cameraError = 'No se encontró ninguna cámara disponible.');
        return;
      }

      /// ✅ Configuración correcta del controlador
      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _cameraError = null;
      });

      await _startImageStream();
    } catch (_) {
      controller?.dispose();
      if (!mounted) return;
      setState(() => _cameraError = 'No se pudo inicializar la cámara.');
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;

    try {
      await controller.startImageStream(_onCameraImage);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraError = 'No se pudo iniciar la transmisión de la cámara.');
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages) return;

    try {
      await controller.stopImageStream();
    } catch (_) {}
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (image.planes.isEmpty) return;
    if (_isProcessingFrame || _isCapturingDocument || _isScanningDocument) return;
    if (_result != null) return;

    _isProcessingFrame = true;

    try {
      final controller = _cameraController;
      if (controller == null) return;

      final inputImage = _buildInputImage(image, controller);
      final detection = await _scannerService.scanFromInputImage(inputImage);

      if (detection.hasText) {
        await _handleDetectedText();
      }
    } catch (_) {}
    finally {
      _isProcessingFrame = false;
    }
  }

  /// ✅ Adaptado al nuevo API de ML Kit (2025)
  InputImage _buildInputImage(CameraImage image, CameraController controller) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }

    final bytes = allBytes.done().buffer.asUint8List();

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ?? InputImageRotation.rotation0deg,
        format: InputImageFormatValue.fromRawValue(image.format.raw)
            ?? InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Future<void> _handleDetectedText() async {
    if (_isCapturingDocument) return;

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    _isCapturingDocument = true;

    try {
      await _stopImageStream();

      await _tts.stop();
      _cancelSpeaking = false;
      await _tts.speak('He detectado texto frente a la cámara. Procediendo a escanear.');

      final file = await controller.takePicture();
      if (!mounted) return;

      setState(() {
        _capturedFile = file;
        _result = null;
        _isScanningDocument = true;
      });

      final scanResult = await _scannerService.scan(file.path);

      if (!mounted) return;

      setState(() {
        _result = scanResult;
        _isScanningDocument = false;
      });

      if (scanResult.hasText) {
        await _readDetectedText(scanResult);
      } else {
        _showMessage('No se detectó texto legible en el documento.');
      }

    } catch (_) {
      if (!mounted) return;
      setState(() => _isScanningDocument = false);
      _showMessage('No se pudo escanear el documento. Inténtalo de nuevo.');
      await _restartScanning();
    } finally {
      _isCapturingDocument = false;
    }
  }

  Future<void> _restartScanning() async {
    await _stopSpeaking();
    setState(() {
      _capturedFile = null;
      _result = null;
      _isScanningDocument = false;
    });

    _cancelSpeaking = false;
    await _startImageStream();
  }

  Future<void> _readDetectedText(DocumentScanResult result) async {
    final phrases = result.phrases;
    if (phrases.isEmpty) return;

    await _tts.stop();
    _cancelSpeaking = false;

    if (!mounted) return;
    setState(() => _isSpeaking = true);

    try {
      for (final phrase in phrases) {
        if (_cancelSpeaking) return;
        await _tts.speak(phrase.trim());
      }
    } finally {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopSpeaking() async {
    _cancelSpeaking = true;
    await _tts.stop();

    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _stopImageStream();
    _cameraController?.dispose();
    _tts.stop();
    _scannerService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _capturedFile != null && _result != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Lector de Documentos')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_isScanningDocument) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Expanded(
                child: hasResult
                    ? _ResultView(
                  imagePath: _capturedFile!.path,
                  result: _result!,
                  onReadAgain: () => _readDetectedText(_result!),
                  isSpeaking: _isSpeaking,
                  onStopSpeaking: _stopSpeaking,
                )
                    : _buildCameraPreview(),
              ),
              const SizedBox(height: 12),
              if (hasResult)
                FilledButton.icon(
                  onPressed: _restartScanning,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Escanear otro documento"),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text("Volver al menú"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraStatusMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final bool showLoader;

  const _CameraStatusMessage({
    required this.icon,
    required this.message,
    this.showLoader = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Icon(icon, size: 70, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (showLoader)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final String imagePath;
  final DocumentScanResult result;
  final VoidCallback onReadAgain;
  final VoidCallback onStopSpeaking;
  final bool isSpeaking;

  const _ResultView({
    required this.imagePath,
    required this.result,
    required this.onReadAgain,
    required this.onStopSpeaking,
    required this.isSpeaking,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SingleChildScrollView(
      child: Column(
        children: [
          DocumentPreview(imagePath: imagePath, blocks: result.blocks),
          const SizedBox(height: 16),
          Row(
            children: [
              Text("Texto detectado", style: textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: isSpeaking ? onStopSpeaking : onReadAgain,
                icon: Icon(isSpeaking ? Icons.stop : Icons.volume_up),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...result.phrases.map(
                (p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(p, style: textTheme.bodyLarge),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
