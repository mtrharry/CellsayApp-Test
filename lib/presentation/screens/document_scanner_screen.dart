import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

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
  final _picker = ImagePicker();
  final _scannerService = DocumentScannerService();
  final _tts = FlutterTts();

  XFile? _capturedFile;
  DocumentScanResult? _result;
  bool _isProcessing = false;
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _configureTts();
  }

  Future<void> _configureTts() async {
    await _tts.setLanguage('es-MX');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.awaitSpeakCompletion(true);
  }

  Future<void> _scanDocument() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (file == null) {
        return;
      }

      setState(() {
        _isProcessing = true;
        _capturedFile = file;
        _result = null;
      });

      final result = await _scannerService.scan(file.path);

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _result = result;
      });

      if (result.hasText) {
        await _speak(result.text);
      } else {
        _showMessage('No se detectó texto legible en el documento.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showMessage('No se pudo escanear el documento. Inténtalo de nuevo.');
    }
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    setState(() => _isSpeaking = true);
    await _tts.speak(text);
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
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
              if (_isProcessing) const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Expanded(
                child: hasResult
                    ? _ResultView(
                        imagePath: file.path,
                        result: result,
                        onReadAgain: () => _speak(result.text),
                        isSpeaking: _isSpeaking,
                        onStopSpeaking: _stopSpeaking,
                      )
                    : _EmptyState(onScanPressed: _scanDocument),
              ),
              const SizedBox(height: 16),
              if (hasResult) ...[
                FilledButton.icon(
                  onPressed: _scanDocument,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Leer otro documento'),
                ),
                const SizedBox(height: 12),
              ] else ...[
                FilledButton.icon(
                  onPressed: _scanDocument,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Escanear documento'),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScanPressed});

  final VoidCallback onScanPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.document_scanner_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          const Text(
            'Escanea un documento para extraer el texto. '
            'El documento se detectará automáticamente y podrás escucharlo.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onScanPressed,
            child: const Text('Comenzar escaneo'),
          ),
        ],
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
                onPressed: isSpeaking ? onStopSpeaking : onReadAgain,
                tooltip: isSpeaking ? 'Detener lectura' : 'Escuchar texto',
                icon: Icon(isSpeaking ? Icons.stop_circle : Icons.volume_up),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              result.hasText
                  ? result.text
                  : 'No se detectó texto en el documento.',
              style: textTheme.bodyLarge,
            ),
          ),
        ],
      ),
    );
  }
}
