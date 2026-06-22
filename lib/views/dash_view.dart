import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';

class DashView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const DashView({super.key, required this.telemetry, required this.settings});

  @override
  Widget build(BuildContext context) {
    if (telemetry == null) {
      return const Center(child: Text('Waiting for telemetry…'));
    }

    final speedStr = telemetry!.speed.toStringAsFixed(1);
    final unitStr = settings?.mph == true ? 'MPH' : 'KM/H';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(speedStr, style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text(unitStr, style: const TextStyle(fontSize: 24, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(label: 'WATTS', value: '${telemetry!.watts}'),
              _Stat(label: 'VOLTS', value: telemetry!.volts.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(label: 'MOTOR', value: '${telemetry!.motorTempC}°C'),
              _Stat(label: 'ESC', value: '${telemetry!.escTempC}°C'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600)),
        Text(label, style: const TextStyle(fontSize: 16, color: Colors.grey)),
      ],
    );
  }
}
