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
  bool _cancelSpeaking = false;

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
        await _readDetectedText(result, withAnnouncement: true);
      } else {
        _showMessage('No se detectó texto legible en el documento.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      _showMessage('No se pudo escanear el documento. Inténtalo de nuevo.');
    }
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
                        onReadAgain: () => _readDetectedText(result),
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
