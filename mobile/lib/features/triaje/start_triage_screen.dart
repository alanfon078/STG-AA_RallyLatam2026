import 'package:flutter/material.dart';

import '../../core/theme/oled_theme.dart';
import 'start_triage_controller.dart';
import 'start_triage_model.dart';

export 'start_triage_controller.dart';

/// Pantalla Flutter de Triaje Médico START (SCI-207) en el ACV.
/// Tema OLED Black (#000000) y botones gigantes (>= 64x64 dp) para operación con guantes en <= 3 toques.
class StartTriageScreen extends StatefulWidget {
  final StartTriageController controller;

  const StartTriageScreen({Key? key, required this.controller})
      : super(key: key);

  @override
  State<StartTriageScreen> createState() => _StartTriageScreenState();
}

class _StartTriageScreenState extends State<StartTriageScreen> {
  String _statusMessage = 'ACV Listo — Toque un color START o dicte por voz';

  void _onTapColor(StartColor color) {
    setState(() {
      widget.controller.incrementColor(color);
      _statusMessage =
          'Registrado ${color.name} (Total: ${widget.controller.victims.length})';
    });
  }

  Future<void> _onTransmit() async {
    final entry = await widget.controller.transmitAcvTriage(
      acvName: 'ACV Principal',
      lat: 20.1402,
      lon: -101.1798,
    );
    setState(() {
      _statusMessage =
          'SCI-207 enviado a cola BLE (${entry.compactId} · Sev ${entry.frame.severity})';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return Container(
      color: const Color(StgOledThemeSpec.backgroundHex),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SCI-207 · TRIAJE START (ACV)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _StartButton(
                  label: 'ROJO (INMEDIATO)',
                  count: c.rojoCount,
                  color: const Color(StgOledThemeSpec.startRojoHex),
                  textColor: Colors.white,
                  onPressed: () => _onTapColor(StartColor.ROJO),
                ),
                _StartButton(
                  label: 'AMARILLO (DEMORADO)',
                  count: c.amarilloCount,
                  color: const Color(StgOledThemeSpec.startAmarilloHex),
                  textColor: Colors.black,
                  onPressed: () => _onTapColor(StartColor.AMARILLO),
                ),
                _StartButton(
                  label: 'VERDE (LEVE)',
                  count: c.verdeCount,
                  color: const Color(StgOledThemeSpec.startVerdeHex),
                  textColor: Colors.black,
                  onPressed: () => _onTapColor(StartColor.VERDE),
                ),
                _StartButton(
                  label: 'NEGRO (FALLECIDO)',
                  count: c.negroCount,
                  color: const Color(StgOledThemeSpec.startNegroHex),
                  textColor: Colors.white,
                  onPressed: () => _onTapColor(StartColor.NEGRO),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: StgOledThemeSpec.minGloveButtonHeightDp,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white, width: 2),
              ),
              onPressed: () {
                setState(() {
                  c.applyVoiceDictation('un rojo dos amarillos');
                  _statusMessage = 'Dictado por voz offline aplicado';
                });
              },
              icon: const Icon(Icons.mic, size: 28),
              label: const Text(
                'DICTADO POR VOZ OFFLINE',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 72,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(StgOledThemeSpec.sciPcOrangeHex),
                foregroundColor: Colors.black,
              ),
              onPressed: _onTransmit,
              icon: const Icon(Icons.Bluetooth_connected, size: 28),
              label: const Text(
                'TRANSMITIR SCI-207 VÍA BLE / LORA',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            style: const TextStyle(color: Colors.amberAccent, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _StartButton({
    required this.label,
    required this.count,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: StgOledThemeSpec.minGloveButtonWidthDp,
      height: StgOledThemeSpec.minGloveButtonHeightDp,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
