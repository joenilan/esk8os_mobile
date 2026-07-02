import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Turn a raw BLE error into a rider-readable message. Android's GATT stack
/// reports most transient failures as the generic code 133; callers that can
/// retry should do so before ever surfacing this text.
String friendlyBleError(Object e) {
  if (e is FlutterBluePlusException) {
    final code = e.code ?? 0;
    if (code == 133) {
      return "The board didn't respond. Move closer and try again.";
    }
    if (code == 8 || code == 19) {
      return 'The board dropped the connection. Make sure it’s powered on '
          'and try again.';
    }
    if (e.description != null && e.description!.isNotEmpty) {
      return 'Bluetooth error: ${e.description}';
    }
    return 'Bluetooth error. Try again.';
  }
  final s = e.toString();
  if (s.contains('timeout') || s.contains('Timeout')) {
    return 'Timed out. Bring the board closer and try again.';
  }
  return 'Something went wrong. Try again.';
}
