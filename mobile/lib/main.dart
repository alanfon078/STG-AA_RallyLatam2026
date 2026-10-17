import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'binary_frame.dart';

void main() => runApp(const BrigadistaApp());

class BrigadistaApp extends StatelessWidget {
  const BrigadistaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STG-AA · Brigadista SCI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111111)),
        useMaterial3: true,
      ),
      home: const TriageHomePage(),
    );
  }
}

class TriageHomePage extends StatefulWidget {
  const TriageHomePage({super.key});

  @override
  State<TriageHomePage> createState() => _TriageHomePageState();
}

class _TriageHomePageState extends State<TriageHomePage> {
  int _seq = 1;
  String _selectedZone = '20.1355,-101.1845,2';
  int _rojo = 2, _amarillo = 2, _verde = 1, _negro = 0;
  double _severity = 9;
  String _status = 'Listo para empaquetar trama de 25 bytes (FLAG_BRIGADISTA).';

  Future<void> _transmit() async {
    final parts = _selectedZone.split(',');
    final total = (_rojo + _amarillo + _verde + _negro).clamp(1, 999);
    final frame = StgFrame(
      kind: int.parse(parts[2]),
      seq: _seq++,
      nodeTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lat: double.parse(parts[0]),
      lon: double.parse(parts[1]),
      severity: _severity.round(),
      affected: total,
    );
    final hex = frame.encodeHex();

    setState(() => _status = 'Transmitiendo trama 25B: $hex');
    try {
      await http.post(
        Uri.parse('http://127.0.0.1:8000/ingest/frame'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'hex': hex}),
      );
      setState(() => _status = 'CONFIRMADO · Trama 25B recibida por el Puesto de Comando: $hex');
    } catch (_) {
      setState(() => _status = 'Trama 25B generada para BLE/LoRa: $hex');
    }
  }

  Widget _counterCard(String title, String sub, int value, Color color, ValueChanged<int> onDelta) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: color, width: 5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => onDelta(-1), icon: const Icon(Icons.remove)),
              Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => onDelta(1), icon: const Icon(Icons.add)),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text(
          'STG-AA · Dictamen Táctico SCI-201 / START',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<String>(
                value: _selectedZone,
                decoration: const InputDecoration(
                  labelText: '1. Zona de intervención a verificar',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: '20.1355,-101.1845,2', child: Text('Zona 02 · Sector Sur (Sin verificar)')),
                  DropdownMenuItem(value: '20.1475,-101.1710,1', child: Text('Zona 03 · Sector Oriente (Sin verificar)')),
                  DropdownMenuItem(value: '20.1410,-101.1790,0', child: Text('Zona 01 · Centro (Actualizar)')),
                ],
                onChanged: (v) => setState(() => _selectedZone = v!),
              ),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.35,
                children: [
                  _counterCard('ROJO · INMEDIATO', 'Riesgo vital', _rojo, const Color(0xFFB91C1C),
                      (d) => setState(() => _rojo = (_rojo + d).clamp(0, 99))),
                  _counterCard('AMARILLO · DEMORADO', 'Grave estable', _amarillo, const Color(0xFFB45309),
                      (d) => setState(() => _amarillo = (_amarillo + d).clamp(0, 99))),
                  _counterCard('VERDE · MENOR', 'Ambulatorio', _verde, const Color(0xFF15803D),
                      (d) => setState(() => _verde = (_verde + d).clamp(0, 99))),
                  _counterCard('NEGRO · FALLECIDO', 'Sin signos', _negro, const Color(0xFF27272A),
                      (d) => setState(() => _negro = (_negro + d).clamp(0, 99))),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('3. Severidad en sitio: ${_severity.round()} / 10',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Slider(
                      value: _severity,
                      min: 1,
                      max: 10,
                      divisions: 9,
                      activeColor: const Color(0xFFB91C1C),
                      onChanged: (v) => setState(() => _severity = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 50,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111111)),
                  onPressed: _transmit,
                  child: const Text('Transmitir dictamen verificado (LoRa)'),
                ),
              ),
              const SizedBox(height: 12),
              Text(_status, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
