import 'dart:ui';

/// Stores the OCR result for a scanned document including the raw text and
/// the detected text blocks with their bounding boxes.
class DocumentScanResult {
  const DocumentScanResult({
    required this.text,
    required this.blocks,
  });

  /// Concatenated text extracted from the document.
  final String text;

  /// Individual text blocks that compose the final result.
  final List<DocumentTextBlock> blocks;

  /// Whether the scan contains any readable text.
  bool get hasText => text.trim().isNotEmpty;

  /// Phrases extracted from each recognized block, split by line breaks.
  List<String> get phrases {
    final segments = blocks
        .expand(
          (block) => block.text
              .split(RegExp(r'[\r\n]+'))
              .map((segment) => segment.trim()),
        )
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);

    if (segments.isNotEmpty) {
      return List.unmodifiable(segments);
    }

    final fallback = text.trim();
    if (fallback.isEmpty) {
      return const [];
    }

    return List.unmodifiable(<String>[fallback]);
  }
}

/// Represents a single recognized text block within a document.
class DocumentTextBlock {
  const DocumentTextBlock({
    required this.text,
    required this.boundingBox,
  });

  /// Raw text contained inside the block.
  final String text;

  /// Bounding box for the text block in the image coordinate space.
  final Rect boundingBox;
}
