// Archivo: lib/main.dart

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo_example/presentation/screens/camera_inference_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/menu_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/money_detector_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/single_image_screen.dart';
import 'package:ultralytics_yolo_example/presentation/screens/text_reader_screen.dart';
import 'package:ultralytics_yolo_example/models/models.dart'; // NECESARIO para ModelType

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CellSay',
      home: const MenuScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/money') {
          // Ruta original de 'dinero' (Modo Voz/Single-Shot)
          return MaterialPageRoute(
            builder: (_) => const MoneyDetectorScreen(),
            settings: settings,
          );
        }
        if (settings.name == '/camera') {
          final target = _resolveCameraTarget(settings.arguments);
          if (target == _CameraTarget.money) {
            // CAMBIO CLAVE: Usamos CameraInferenceScreen con el modelo de Billetes32
            return MaterialPageRoute(
              builder: (_) => const CameraInferenceScreen(
                modelType: ModelType.Billetes32, // Cargamos billetes32.tflite
              ),
              settings: settings,
            );
          }
          // Si es 'objects' o default
          return MaterialPageRoute(
            builder: (_) => const CameraInferenceScreen(
              modelType: ModelType.Interior, // Modelo predeterminado (yolo11n)
            ),
            settings: settings,
          );
        }
        if (settings.name == '/single-image') {
          return MaterialPageRoute(
            builder: (_) => const SingleImageScreen(),
            settings: settings,
          );
        }
        if (settings.name == '/text-reader') {
          return MaterialPageRoute(
            builder: (_) => const TextReaderScreen(),
            settings: settings,
          );
        }

        return null;
      },
    );
  }
}

enum _CameraTarget { objects, money }

_CameraTarget _resolveCameraTarget(Object? arguments) {
  if (arguments is Map) {
    final preset = arguments['preset'] ?? arguments['model'];
    if (preset is String && _isMoneyPreset(preset)) {
      // Si se pasa 'dinero' o 'money' como argumento
      return _CameraTarget.money;
    }
  } else if (arguments is String && _isMoneyPreset(arguments)) {
    return _CameraTarget.money;
  }
  return _CameraTarget.objects;
}

bool _isMoneyPreset(String value) {
  final normalized = value.toLowerCase();
  return normalized == 'money' || normalized == 'dinero';
}