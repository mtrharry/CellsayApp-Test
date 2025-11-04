import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/document_scan_result.dart';

/// Provides OCR capabilities to extract text from captured document images.
class DocumentScannerService {
  DocumentScannerService()
      : _textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );

  final TextRecognizer _textRecognizer;

  /// Processes the image located at [imagePath] and returns the recognized text
  /// as a [DocumentScanResult].
  Future<DocumentScanResult> scan(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _textRecognizer.processImage(inputImage);

    final blocks = recognizedText.blocks
        .map(
          (block) => DocumentTextBlock(
            text: block.text.trim(),
            boundingBox: block.boundingBox,
          ),
        )
        .toList();

    return DocumentScanResult(
      text: recognizedText.text.trim(),
      blocks: blocks,
    );
  }

  /// Releases ML Kit resources when the service is no longer needed.
  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
