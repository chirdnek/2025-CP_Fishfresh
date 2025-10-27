// ignore_for_file: unused_import

import 'fish_model_mobilenet.dart';
import 'fish_model_efficient.dart';
import 'fish_model_resnet.dart';

class ModelDef {
  final String name;
  final String assetPath;
  final String labelsPath;
  const ModelDef(this.name, this.assetPath, this.labelsPath);
}

class ModelRegistry {
  static const mobilenet = ModelDef(
    'MobileNetV2',
    'assets/model/mobilenetv2_torchvision_Oct_25_3-08_pm_float32.tflite',
    'assets/model/classes_flat.json',
  );
  static const efficient = ModelDef(
    'EfficientNet-Lite2',
    'assets/model/efficientnetv2_Oct_19_4-18_am_float32.tflite',
    'assets/model/classes_flat.json',
  );
  static const resnet = ModelDef(
    'ResNet-50',
    'assets/model/resnet50Oct_24_5-19_am_float32.tflite',
    'assets/model/classes_flat.json',
  );

  static const all = <ModelDef>[mobilenet, efficient, resnet];
}
