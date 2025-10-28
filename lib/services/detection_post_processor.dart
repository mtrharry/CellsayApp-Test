import 'dart:math';
import 'dart:ui';
import 'package:ultralytics_yolo/models/yolo_result.dart';
import '../core/vision/detection_geometry.dart';
import '../models/detection_insight.dart';

/// Applies additional post processing to YOLO detections improving NMS
/// and extracting semantic information useful for voice feedback.
class DetectionPostProcessor {
  DetectionPostProcessor({
    double iouThreshold = 0.45,
    double closeObstacleAreaThreshold = 0.22,
  })  : _iouThreshold = iouThreshold,
        _closeObstacleAreaThreshold = closeObstacleAreaThreshold;

  final List<_TrackedDetection> _previousDetections = <_TrackedDetection>[];
  double _iouThreshold;
  double _closeObstacleAreaThreshold;

  void updateThresholds({double? iouThreshold, double? closeObstacleAreaThreshold}) {
    if (iouThreshold != null) {
      _iouThreshold = iouThreshold.clamp(0.05, 0.95);
    }
    if (closeObstacleAreaThreshold != null) {
      _closeObstacleAreaThreshold = closeObstacleAreaThreshold.clamp(0.05, 0.9);
    }
  }

  void clearHistory() {
    _previousDetections.clear();
  }

  ProcessedDetections process(List<YOLOResult> rawResults) {
    if (rawResults.isEmpty) {
      _previousDetections.clear();
      return ProcessedDetections.empty;
    }

    final candidates = <_DetectionCandidate>[];
    for (final result in rawResults) {
      try {
        candidates.add(_DetectionCandidate.fromResult(result));
      } catch (_) {
        // Ignore malformed detections that cannot be converted.
      }
    }

    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final selected = <_DetectionCandidate>[];
    final closeObstacles = <String>[];
    final movementWarnings = <String>[];
    TrafficLightSignal trafficSignal = TrafficLightSignal.unknown;

    for (final candidate in candidates) {
      bool shouldSelect = true;
      for (final kept in selected) {
        if (kept.label == candidate.label) {
          final iou = _computeIoU(kept.boundingBox, candidate.boundingBox);
          if (iou > _iouThreshold) {
            shouldSelect = false;
            break;
          }
        }
      }

      if (!shouldSelect) continue;
      selected.add(candidate);

      if (candidate.normalizedArea >= _closeObstacleAreaThreshold) {
        closeObstacles.add(candidate.label);
      }

      final movementWarning = _detectMovement(candidate);
      if (movementWarning != null) {
        movementWarnings.add(movementWarning);
      }

      trafficSignal = _mergeTrafficSignal(trafficSignal, candidate.trafficLightSignal);
    }

    _updateHistory(selected);

    return ProcessedDetections(
      filteredResults: selected.map((e) => e.original).toList(),
      closeObstacleLabels: closeObstacles,
      trafficLightSignal: trafficSignal,
      movementWarnings: movementWarnings,
    );
  }

  void _updateHistory(List<_DetectionCandidate> selected) {
    _previousDetections
      ..clear()
      ..addAll(selected.map(_TrackedDetection.fromCandidate));
  }

  String? _detectMovement(_DetectionCandidate candidate) {
    final previous = _previousDetections.where(
      (tracked) => tracked.label == candidate.label,
    );

    _TrackedDetection? bestMatch;
    double bestIoU = 0;
    for (final tracked in previous) {
      final iou = _computeIoU(tracked.boundingBox, candidate.boundingBox);
      if (iou > bestIoU) {
        bestIoU = iou;
        bestMatch = tracked;
      }
    }

    if (bestMatch == null || bestIoU < 0.2) {
      return null;
    }

    final growth = candidate.normalizedArea / (bestMatch.normalizedArea + 1e-6);
    final approaching = candidate.boundingBox.center.dy < bestMatch.boundingBox.center.dy + 0.05;

    if (growth > 1.6 && approaching) {
      return '${candidate.label} acercándose rápidamente';
    }
    return null;
  }

  TrafficLightSignal _mergeTrafficSignal(
    TrafficLightSignal current,
    TrafficLightSignal candidate,
  ) {
    if (candidate == TrafficLightSignal.unknown) return current;
    if (current == TrafficLightSignal.unknown) return candidate;
    if (current == candidate) return current;
    // Prefer red over green in case of conflict for safety.
    return TrafficLightSignal.red;
  }

  double _computeIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    final intersectionArea = max(0.0, intersection.width) * max(0.0, intersection.height);
    final areaA = max(0.0, a.width) * max(0.0, a.height);
    final areaB = max(0.0, b.width) * max(0.0, b.height);
    final union = areaA + areaB - intersectionArea + 1e-6;
    return union <= 0 ? 0 : intersectionArea / union;
  }
}

class _DetectionCandidate {
  _DetectionCandidate({
    required this.original,
    required this.boundingBox,
    required this.confidence,
    required this.label,
    required this.trafficLightSignal,
  }) : normalizedArea = max(0.0, boundingBox.width) * max(0.0, boundingBox.height);

  final YOLOResult original;
  final Rect boundingBox;
  final double confidence;
  final String label;
  final double normalizedArea;
  final TrafficLightSignal trafficLightSignal;

  factory _DetectionCandidate.fromResult(YOLOResult result) {
    final rect = extractBoundingBox(result);
    final confidence = extractConfidence(result) ?? 0.0;
    final label = extractLabel(result);
    final signal = _inferTrafficLightSignal(result, label);

    if (rect == null) {
      throw ArgumentError('Detection without bounding box');
    }

    return _DetectionCandidate(
      original: result,
      boundingBox: rect,
      confidence: confidence,
      label: label,
      trafficLightSignal: signal,
    );
  }
}

class _TrackedDetection {
  _TrackedDetection({
    required this.label,
    required this.boundingBox,
    required this.normalizedArea,
  });

  final String label;
  final Rect boundingBox;
  final double normalizedArea;

  factory _TrackedDetection.fromCandidate(_DetectionCandidate candidate) {
    return _TrackedDetection(
      label: candidate.label,
      boundingBox: candidate.boundingBox,
      normalizedArea: candidate.normalizedArea,
    );
  }
}

TrafficLightSignal _inferTrafficLightSignal(YOLOResult result, String label) {
  final normalizedLabel = label.toLowerCase();
  if (normalizedLabel.contains('semaforo') || normalizedLabel.contains('traffic')) {
    if (normalizedLabel.contains('red') || normalizedLabel.contains('rojo')) {
      return TrafficLightSignal.red;
    }
    if (normalizedLabel.contains('green') || normalizedLabel.contains('verde')) {
      return TrafficLightSignal.green;
    }
  }

  final dynamic dynamicResult = result;
  try {
    final colorValue = dynamicResult.color;
    final colorString = colorValue?.toString().toLowerCase();
    if (colorString != null) {
      if (colorString.contains('red') || colorString.contains('rojo')) {
        return TrafficLightSignal.red;
      }
      if (colorString.contains('green') || colorString.contains('verde')) {
        return TrafficLightSignal.green;
      }
    }
  } catch (_) {}

  final map = _mapRepresentation(dynamicResult);
  if (map != null) {
    final colorString = map['color']?.toString().toLowerCase();
    if (colorString != null) {
      if (colorString.contains('red') || colorString.contains('rojo')) {
        return TrafficLightSignal.red;
      }
      if (colorString.contains('green') || colorString.contains('verde')) {
        return TrafficLightSignal.green;
      }
    }
  }

  return TrafficLightSignal.unknown;
}

Map<String, dynamic>? _mapRepresentation(dynamic value) {
  try {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry('$key', val));
    }
    final jsonValue = value?.toJson();
    if (jsonValue is Map) {
      return jsonValue.map((key, dynamic val) => MapEntry('$key', val));
    }
  } catch (_) {}
  return null;
}
