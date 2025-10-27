// lib/services/fish_runtime.dart
// ignore_for_file: unnecessary_brace_in_string_interps, avoid_dynamic_calls

import 'dart:developer' as dev;

import 'model_registry.dart';
// Keep these imports so the classes are visible to the analyzer.
import 'fish_model_mobilenet.dart';
import 'fish_model_efficient.dart';
import 'fish_model_resnet.dart';

/// Central runtime that owns exactly one model instance at a time.
/// Uses `dynamic` so it works even if wrappers don't share a common base.
class FishRuntime {
  dynamic _model; // tolerant to wrappers not extending the same base
  ModelDef? current;

  Future<void> load(ModelDef def) async {
    await dispose();
    current = def;

    // 1) Construct with NO ARGS (your constructors expect 0 args).
    if (identical(def, ModelRegistry.mobilenet)) {
      // Adjust class name if yours is FishModelMobileNet (capital N) etc.
      _model = FishModelMobilenet();
    } else if (identical(def, ModelRegistry.efficient)) {
      _model = FishModelEfficientLite2();
    } else if (identical(def, ModelRegistry.resnet)) {
      // If your class is FishModelResNet50, change this to FishModelResNet50().
      _model = FishModelResNet();
    } else {
      throw ArgumentError('Unknown ModelDef: ${def.name}');
    }

    // 2) Try to pass model/labels paths via any of several common APIs your wrappers might have.
    _maybeConfigurePaths(_model, def.assetPath, def.labelsPath);

    // 3) Init the model.
    await _model.init();

    // Optional warm-up (safe to ignore if your wrapper doesn't support it)
    try {
      // await _model.predict(tinyImagePath);
    } catch (_) {}
  }

  /// Tries a few common method/field patterns to inject paths without knowing the exact API.
  void _maybeConfigurePaths(dynamic m, String modelPath, String labelsPath) {
    // Named method: configure(modelPath: ..., labelsPath: ...)
    try { m.configure(modelPath: modelPath, labelsPath: labelsPath); return; } catch (_) {}
    // Named method: setAssets(modelPath: ..., labelsPath: ...)
    try { m.setAssets(modelPath: modelPath, labelsPath: labelsPath); return; } catch (_) {}
    // Positional method: setPaths(modelPath, labelsPath)
    try { m.setPaths(modelPath, labelsPath); return; } catch (_) {}
    // Individual setters or public fields
    try { m.setModelPath(modelPath); } catch (_) {}
    try { m.setLabelsPath(labelsPath); } catch (_) {}
    try { m.modelPath = modelPath; } catch (_) {}
    try { m.labelsPath = labelsPath; } catch (_) {}
    // If none exist, wrappers likely read paths internally (e.g., hardcoded asset names) — that's fine.
  }

  Future<void> dispose() async {
    try {
      if (_model != null) {
        try { _model.dispose(); } catch (_) {}
      }
    } finally {
      _model = null;
      current = null;
    }
  }

  bool get ready {
    if (_model == null) return false;
    try {
      final v = _model.isInitialized;
      return v == true;
    } catch (_) {
      // If wrapper doesn't expose isInitialized, assume ready after init()
      return true;
    }
  }

  dynamic get model {
    final m = _model;
    if (m == null) {
      throw StateError('Model not loaded. Call load(ModelDef) first.');
    }
    return m;
    }

  Future<Map<String, dynamic>> predictWithTiming(String path) async {
    final sw = Stopwatch()..start();
    final outDynamic = await model.predict(path);
    sw.stop();

    final ms = sw.elapsedMilliseconds;
    final Map<String, dynamic> out =
        (outDynamic is Map<String, dynamic>) ? outDynamic : <String, dynamic>{'raw': outDynamic};

    out['latency_ms'] = ms;
    dev.log('[BENCH] ${current?.name} $ms ms');
    return out;
  }
}
