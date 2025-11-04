import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/document_scan_result.dart';
import '../../services/document_scanner_service.dart';
import '../widgets/document_preview.dart';

/// Allows the user to capture a document and extract its text using OCR.
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
        setState(() {
          _cameraError =
              'Se requiere el permiso de cámara para escanear documentos.';
        });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _cameraError = 'No se encontró ninguna cámara disponible.';
        });
        return;
      }

      controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.setFlashMode(FlashMode.off);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _isCameraInitialized = true;
        _cameraError = null;
      });

      await _startImageStream();
    } catch (_) {
      await controller?.dispose();
      if (!mounted) return;
      setState(() {
        _cameraError = 'No se pudo inicializar la cámara.';
      });
    }
  }

  Future<void> _startImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.startImageStream(_onCameraImage);
      if (!mounted) return;
      setState(() {
        _cameraError = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'No se pudo iniciar la transmisión de la cámara.';
      });
    }
  }

  Future<void> _stopImageStream() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (!controller.value.isStreamingImages) {
      return;
    }
    try {
      await controller.stopImageStream();
    } catch (_) {
      // Ignorar errores al detener la transmisión para evitar bloquear el flujo.
    }
  }

  Future<void> _onCameraImage(CameraImage image) async {
    if (_isProcessingFrame || _isCapturingDocument || _isScanningDocument) {
      return;
    }
    if (_result != null) {
      return;
    }

    _isProcessingFrame = true;
    try {
      final controller = _cameraController;
      if (controller == null) {
        return;
      }

      final inputImage = _buildInputImage(image, controller);
      final detection = await _scannerService.scanFromInputImage(inputImage);

      if (detection.hasText) {
        await _handleDetectedText();
      }
    } catch (_) {
      // Ignorar errores de detección en tiempo real.
    } finally {
      _isProcessingFrame = false;
    }
  }

  InputImage _buildInputImage(CameraImage image, CameraController controller) {
    final ui.WriteBuffer allBytes = ui.WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final Uint8List bytes = allBytes.done().buffer.asUint8List();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final rotation = InputImageRotationValue.fromRawValue(
          controller.description.sensorOrientation,
        ) ??
        InputImageRotation.rotation0deg;
    final format = InputImageFormatValue.fromRawValue(image.format.raw) ??
        InputImageFormat.nv21;

    final planeData = image.planes
        .map(
          (plane) => InputImagePlaneMetadata(
            bytesPerRow: plane.bytesPerRow,
            height: plane.height,
            width: plane.width,
          ),
        )
        .toList(growable: false);

    return InputImage.fromBytes(
      bytes: bytes,
      inputImageData: InputImageData(
        size: imageSize,
        imageRotation: rotation,
        inputImageFormat: format,
        planeData: planeData,
      ),
    );
  }

  Future<void> _handleDetectedText() async {
    if (_isCapturingDocument) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    _isCapturingDocument = true;
    try {
      await _stopImageStream();

      await _tts.stop();
      _cancelSpeaking = false;
      await _speakSegment(
        'He detectado texto frente a la cámara. Procediendo a escanear.',
      );

      final file = await controller.takePicture();

      if (!mounted) {
        return;
      }

      setState(() {
        _capturedFile = file;
        _result = null;
        _isScanningDocument = true;
      });

      final scanResult = await _scannerService.scan(file.path);

      if (!mounted) {
        return;
      }

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
      if (!mounted) {
        return;
      }
      setState(() {
        _isScanningDocument = false;
      });
      _showMessage('No se pudo escanear el documento. Inténtalo de nuevo.');
      await _restartScanning();
    } finally {
      _isCapturingDocument = false;
    }
  }

  Future<void> _restartScanning() async {
    await _stopSpeaking();

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _capturedFile = null;
      _result = null;
      _isScanningDocument = false;
    });

    _cancelSpeaking = false;
    await _startImageStream();
  }

  Widget _buildCameraPreview() {
    final error = _cameraError;
    if (error != null) {
      return _CameraStatusMessage(
        icon: Icons.error_outline,
        message: error,
      );
    }

    final controller = _cameraController;
    if (controller == null || !_isCameraInitialized) {
      return const _CameraStatusMessage(
        icon: Icons.photo_camera_outlined,
        message: 'Inicializando cámara...',
        showLoader: true,
      );
    }

    final statusText = _isScanningDocument
        ? 'Escaneando documento...'
        : 'Buscando texto en el documento';

    final statusIcon =
        _isScanningDocument ? Icons.hourglass_bottom : Icons.search_rounded;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _ScannerStatusBubble(
              icon: statusIcon,
              text: statusText,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _readDetectedText(
    DocumentScanResult result, {
    bool withAnnouncement = false,
  }) async {
    final phrases = result.phrases;
    if (phrases.isEmpty) {
      return;
    }

    await _tts.stop();
    _cancelSpeaking = false;
    if (!mounted) return;
    setState(() => _isSpeaking = true);

    try {
      if (withAnnouncement) {
        await _speakSegment('He detectado texto tomando captura.');
        if (_cancelSpeaking) return;
        await _waitWithCancellation(const Duration(seconds: 2));
        if (_cancelSpeaking) return;
      }

      for (final phrase in phrases) {
        await _speakSegment(phrase);
        if (_cancelSpeaking) {
          return;
        }
      }
    } finally {
      if (!mounted) return;
      setState(() => _isSpeaking = false);
    }
  }

  Future<void> _speakSegment(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _cancelSpeaking) {
      return;
    }

    try {
      await _tts.speak(trimmed);
    } catch (_) {
      // Ignore speech errors to avoid interrupting the flow.
    }
  }

  Future<void> _waitWithCancellation(Duration duration) async {
    const step = Duration(milliseconds: 100);
    var elapsed = Duration.zero;

    while (!_cancelSpeaking && elapsed < duration) {
      final remaining = duration - elapsed;
      final wait = remaining < step ? remaining : step;
      if (wait <= Duration.zero) {
        break;
      }
      await Future.delayed(wait);
      elapsed += wait;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopSpeaking() async {
    _cancelSpeaking = true;
    await _tts.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    final controller = _cameraController;
    if (controller != null) {
      unawaited(_stopImageStream());
      unawaited(controller.dispose());
    }
    unawaited(_tts.stop());
    unawaited(_scannerService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final file = _capturedFile;
    final result = _result;
    final hasResult = file != null && result != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lector de Documentos'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_isScanningDocument) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Expanded(
                child: hasResult
                    ? _ResultView(
                        imagePath: file.path,
                        result: result,
                        onReadAgain: () => _readDetectedText(result),
                        isSpeaking: _isSpeaking,
                        onStopSpeaking: _stopSpeaking,
                      )
                    : _buildCameraPreview(),
              ),
              const SizedBox(height: 16),
              if (hasResult) ...[
                FilledButton.icon(
                  onPressed: _restartScanning,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Escanear otro documento'),
                ),
                const SizedBox(height: 12),
              ] else if (_cameraError == null) ...[
                Text(
                  'Apunta la cámara hacia un documento con texto. '
                  'El escaneo comenzará automáticamente cuando se detecte contenido legible.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al menú'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraStatusMessage extends StatelessWidget {
  const _CameraStatusMessage({
    required this.icon,
    required this.message,
    this.showLoader = false,
  });

  final IconData icon;
  final String message;
  final bool showLoader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 72,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
          if (showLoader) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

class _ScannerStatusBubble extends StatelessWidget {
  const _ScannerStatusBubble({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: textStyle,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.imagePath,
    required this.result,
    required this.onReadAgain,
    required this.onStopSpeaking,
    required this.isSpeaking,
  });

  final String imagePath;
  final DocumentScanResult result;
  final VoidCallback onReadAgain;
  final VoidCallback onStopSpeaking;
  final bool isSpeaking;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final phrases = result.phrases;
    final hasText = result.hasText;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DocumentPreview(
            imagePath: imagePath,
            blocks: result.blocks,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Texto detectado',
                style: textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                onPressed:
                    hasText ? (isSpeaking ? onStopSpeaking : onReadAgain) : null,
                tooltip: isSpeaking ? 'Detener lectura' : 'Escuchar texto',
                icon: Icon(isSpeaking ? Icons.stop_circle : Icons.volume_up),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (hasText)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < phrases.length; i++) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Text(
                      phrases[i],
                      style: textTheme.bodyLarge,
                    ),
                  ),
                  if (i != phrases.length - 1) const SizedBox(height: 12),
                ],
              ],
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'No se detectó texto en el documento.',
                style: textTheme.bodyLarge,
              ),
            ),
        ],
      ),
    );
  }
}
