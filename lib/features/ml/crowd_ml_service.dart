import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

/// ✅ 4 Classes (match training):
/// 0 = low, 1 = medium, 2 = high, 3 = closed
enum CrowdLevel { low, medium, high, closed }

enum _FeatureOrder {
  dayHourClosed, // [day, hour, isClosed]
  hourDayClosed, // [hour, day, isClosed]
}

class CrowdMLService {
  Interpreter? _interpreter;

  late List<double> _mean;  // scaler mean
  late List<double> _scale; // scaler std
  bool _ready = false;

  _FeatureOrder _order = _FeatureOrder.dayHourClosed;

  bool get isReady => _ready;

  Future<void> init() async {
    try {
      // ✅ Keep paths consistent with pubspec assets/ml/
      final scalerRaw = await rootBundle.loadString('assets/ml/scaler.json');
      final scaler = jsonDecode(scalerRaw) as Map<String, dynamic>;

      _mean = (scaler['mean'] as List)
          .map((e) => (e as num).toDouble())
          .toList();
      _scale = (scaler['scale'] as List)
          .map((e) => (e as num).toDouble())
          .toList();

      // ✅ Use cols order if present (stronger than guessing)
      final cols = (scaler['cols'] as List?)?.map((e) => e.toString()).toList();

      if (cols != null && cols.length >= 3) {
        // If cols starts with "hour" -> hourDayClosed
        // else dayHourClosed
        if (cols[0].toLowerCase().contains('hour')) {
          _order = _FeatureOrder.hourDayClosed;
        } else {
          _order = _FeatureOrder.dayHourClosed;
        }
      } else {
        // fallback guess
        if (_mean.isNotEmpty && _mean[0] > 6.0) {
          _order = _FeatureOrder.hourDayClosed;
        } else {
          _order = _FeatureOrder.dayHourClosed;
        }
      }

      if (kDebugMode) {
        debugPrint('✅ scaler loaded mean=$_mean scale=$_scale cols=$cols');
        debugPrint('✅ feature order detected: $_order');
      }

      _interpreter = await Interpreter.fromAsset('assets/ml/crowd_model.tflite');

      _ready = true;
      if (kDebugMode) debugPrint('✅ interpreter loaded, ML ready');
    } catch (e) {
      _ready = false;
      if (kDebugMode) debugPrint('❌ ML init error: $e');
      rethrow;
    }
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _ready = false;
  }

  CrowdLevel? predict({
    required int day,      // 0=Sun..6=Sat
    required int hour,     // 0..23
    required int isClosed, // 0/1
    bool debug = false,
  }) {
    if (!_ready || _interpreter == null) return null;

    // ✅ Build raw input in the correct order
    late List<double> x;
    if (_order == _FeatureOrder.dayHourClosed) {
      x = <double>[day.toDouble(), hour.toDouble(), isClosed.toDouble()];
    } else {
      x = <double>[hour.toDouble(), day.toDouble(), isClosed.toDouble()];
    }

    // ✅ Scale
    final scaled = List<double>.generate(3, (i) {
      final s = (_scale[i] == 0) ? 1.0 : _scale[i];
      return (x[i] - _mean[i]) / s;
    });

    final input = [scaled]; // shape [1,3]

    // ✅ Determine output size dynamically (supports 4-class model)
    final outShape = _interpreter!.getOutputTensor(0).shape; // e.g. [1,4]
    final outLen = (outShape.length >= 2) ? outShape[1] : 4;

    final output = [
      List<double>.filled(outLen, 0.0),
    ];

    _interpreter!.run(input, output);

    final probs = output[0];

    // ✅ pick argmax
    int best = 0;
    double bestVal = probs[0];
    for (int i = 1; i < probs.length; i++) {
      if (probs[i] > bestVal) {
        bestVal = probs[i];
        best = i;
      }
    }

    if (kDebugMode && debug) {
      debugPrint('--- ML DEBUG ---');
      debugPrint('order=$_order');
      debugPrint('raw=$x');
      debugPrint('scaled=$scaled');
      debugPrint('probs=$probs');
      debugPrint('best=$best bestVal=$bestVal');
      debugPrint('--------------');
    }

    // ✅ Expected mapping from training: 0 low, 1 medium, 2 high, 3 closed
    if (probs.length >= 4) {
      return CrowdLevel.values[best];
    }

    // ✅ Safety fallback if you accidentally still have old 3-class model
    // Assume old order was [low, medium, high]
    if (probs.length == 3) {
      return CrowdLevel.values[best]; // low/medium/high only
    }

    return null;
  }
}