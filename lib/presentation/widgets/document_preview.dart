import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../models/document_scan_result.dart';

/// Displays a captured document image with the detected text blocks overlayed.
class DocumentPreview extends StatefulWidget {
  const DocumentPreview({
    super.key,
    required this.imagePath,
    required this.blocks,
  });

  final String imagePath;
  final List<DocumentTextBlock> blocks;

  @override
  State<DocumentPreview> createState() => _DocumentPreviewState();
}

class _DocumentPreviewState extends State<DocumentPreview> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(DocumentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _disposeImage();
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted) return;
      setState(() => _image = frame.image);
    } catch (_) {
      // If the image cannot be decoded we simply keep the preview empty.
    }
  }

  void _disposeImage() {
    final image = _image;
    if (image != null) {
      image.dispose();
    }
    _image = null;
  }

  @override
  void dispose() {
    _disposeImage();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      return AspectRatio(
        aspectRatio: 3 / 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return AspectRatio(
      aspectRatio: image.width / image.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: _DocumentPreviewPainter(
            image: image,
            blocks: widget.blocks,
          ),
        ),
      ),
    );
  }
}

class _DocumentPreviewPainter extends CustomPainter {
  _DocumentPreviewPainter({
    required this.image,
    required this.blocks,
  });

  final ui.Image image;
  final List<DocumentTextBlock> blocks;

  @override
  void paint(Canvas canvas, Size size) {
    final targetRect = Offset.zero & size;
    paintImage(
      canvas: canvas,
      rect: targetRect,
      image: image,
      fit: BoxFit.cover,
    );

    if (blocks.isEmpty) return;

    final scaleX = size.width / image.width;
    final scaleY = size.height / image.height;

    final fillPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.blueAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (final block in blocks) {
      final rect = Rect.fromLTRB(
        block.boundingBox.left * scaleX,
        block.boundingBox.top * scaleY,
        block.boundingBox.right * scaleX,
        block.boundingBox.bottom * scaleY,
      );
      if (rect.isEmpty) continue;
      canvas.drawRect(rect, fillPaint);
      canvas.drawRect(rect, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DocumentPreviewPainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.blocks != blocks;
  }
}
