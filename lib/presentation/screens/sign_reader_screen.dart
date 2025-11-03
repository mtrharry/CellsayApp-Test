import 'package:flutter/material.dart';
import 'package:ultralytics_yolo_example/models/models.dart';
import 'package:ultralytics_yolo_example/presentation/screens/camera_inference_screen.dart';

class SignReaderScreen extends StatelessWidget {
  const SignReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const CameraInferenceScreen(
      modelType: ModelType.LectorCarteles,
      signageMode: true,
    );
  }
}
