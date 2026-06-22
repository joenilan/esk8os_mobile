import 'package:flutter/material.dart';
import '../ble/esk8os_ble.dart';

class PowerView extends StatelessWidget {
  final Telemetry? telemetry;

  const PowerView({super.key, required this.telemetry});

  @override
  Widget build(BuildContext context) {
    if (telemetry == null) {
      return const Center(child: Text('Waiting for telemetry…'));
    }

    final amps = telemetry!.volts > 0 ? (telemetry!.watts / telemetry!.volts).toStringAsFixed(1) : '0.0';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('POWER', style: TextStyle(fontSize: 24, color: Colors.grey, letterSpacing: 4)),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(label: 'BATTERY', value: '${telemetry!.battery}%'),
              _Stat(label: 'VOLTS', value: telemetry!.volts.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _Stat(label: 'AMPS', value: amps),
              _Stat(label: 'WATTS', value: '${telemetry!.watts}'),
            ],
          ),
          const SizedBox(height: 32),
          _Stat(label: 'SESSION WH', value: '${telemetry!.wattHours}'),
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
