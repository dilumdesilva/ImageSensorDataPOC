import 'package:flutter/services.dart';

class LuxSensor {
  static const MethodChannel _channel = MethodChannel('lux_sensor');

  static Future<double?> getLuxValue() async {
    final double? lux = await _channel.invokeMethod('getLuxValue');
    return lux;
  }
}
