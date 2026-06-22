import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../ble/esk8os_ble.dart';

class HudView extends StatelessWidget {
  final Telemetry? telemetry;
  final BoardSettings? settings;

  const HudView({super.key, required this.telemetry, required this.settings});

  @override
  Widget build(BuildContext context) {
    if (telemetry == null) {
      return const Center(child: Text('Waiting for telemetry…', style: TextStyle(color: Colors.white)));
    }

    final speedStr = telemetry!.speed.toStringAsFixed(1);
    final unitStr = settings?.mph == true ? 'MPH' : 'KM/H';
    final distUnit = settings?.mph == true ? 'MI' : 'KM';
    final amps = telemetry!.volts > 0 ? (telemetry!.watts / telemetry!.volts).toStringAsFixed(1) : '0.0';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Top Section: Massive Speed
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  border: Border.all(color: const Color(0xFF333333)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Speed',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          speedStr,
                          style: GoogleFonts.bebasNeue(
                            fontSize: 180,
                            fontWeight: FontWeight.normal,
                            color: Colors.white,
                            height: 1.0,
                            letterSpacing: 2.0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unitStr,
                          style: const TextStyle(
                            fontSize: 24,
                            color: Colors.grey,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(flex: 2),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),

            // Middle Section: Battery Bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                border: Border.all(color: const Color(0xFF333333)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Battery',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: telemetry!.battery / 100.0,
                            minHeight: 12,
                            backgroundColor: const Color(0xFF333333),
                            color: _getBatteryColor(telemetry!.battery),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '${telemetry!.battery}%',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),

            // Bottom Section: Secondary Stats Panel
            Row(
              children: [
                Expanded(child: _CamStatCard(label: 'Range', value: telemetry!.range.toStringAsFixed(1), unit: distUnit)),
                const SizedBox(width: 16),
                Expanded(child: _CamStatCard(label: 'Power', value: '${telemetry!.watts}', unit: 'W')),
                const SizedBox(width: 16),
                Expanded(child: _CamStatCard(label: 'Voltage', value: telemetry!.volts.toStringAsFixed(1), unit: 'V')),
              ],
            ),

            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: _CamStatCard(label: 'Current', value: amps, unit: 'A')),
                const SizedBox(width: 16),
                Expanded(child: _CamStatCard(label: 'Motor', value: '${telemetry!.motorTempC}', unit: '°C')),
                const SizedBox(width: 16),
                Expanded(child: _CamStatCard(label: 'ESC', value: '${telemetry!.escTempC}', unit: '°C')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getBatteryColor(int battery) {
    // Keeping the NZXT feel with solid, slightly muted colors
    if (battery > 50) return const Color(0xFF8B5CF6); // Purple brand color
    if (battery > 20) return const Color(0xFFEAB308); // Yellow
    return const Color(0xFFEF4444); // Red
  }
}

class _CamStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const _CamStatCard({required this.label, required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF333333)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.bebasNeue(
                  fontSize: 48,
                  fontWeight: FontWeight.normal,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
