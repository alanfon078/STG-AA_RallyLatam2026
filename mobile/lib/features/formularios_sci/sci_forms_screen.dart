import 'package:flutter/material.dart';

import '../../core/theme/oled_theme.dart';
import 'sci_forms_controller.dart';
import 'sci_models.dart';

export 'sci_forms_controller.dart';

/// Pantalla Flutter para captura táctica de formularios SCI-201, SCI-211,
/// Bloqueos Viales, Alerta de Alcance de Control (CU-G03) y Transferencia de Mando QR/BLE (CU-G05).
class SciFormsScreen extends StatefulWidget {
  final SciFormsController controller;

  const SciFormsScreen({Key? key, required this.controller}) : super(key: key);

  @override
  State<SciFormsScreen> createState() => _SciFormsScreenState();
}

class _SciFormsScreenState extends State<SciFormsScreen> {
  SpanOfControlStatus? _lastSpanStatus;
  String? _lastQrPayload;
  String _feedback = 'Seleccione acción SCI (máximo 3 toques)';

  Future<void> _sendQuickSci201() async {
    final entry = await widget.controller.submitQuickSci201(
      incidentName: 'Operación Zona Cero',
      commanderName: 'Cmdte. Guardia',
      kind: 0,
      severity: 8,
      securityPerimeter: const [
        GeoPoint(20.139, -101.179),
        GeoPoint(20.141, -101.179),
        GeoPoint(20.141, -101.181),
      ],
      facilities: const [
        SciFacility(
          type: SciFacilityType.PC,
          location: GeoPoint(20.140, -101.180),
          label: 'Puesto de Comando',
        ),
        SciFacility(
          type: SciFacilityType.E,
          location: GeoPoint(20.1395, -101.1805),
          label: 'Área de Espera E',
        ),
        SciFacility(
          type: SciFacilityType.ACV,
          location: GeoPoint(20.1402, -101.1798),
          label: 'ACV Triaje',
        ),
      ],
      situationSummary: 'Perímetro establecido e instalaciones PC/E/ACV activas',
    );
    setState(() {
      _feedback = 'SCI-201 encolado (${entry.compactId})';
    });
  }

  void _checkInResource(int subordinates) {
    final result = widget.controller.registerSci211AndCheckSpan(
      code: 'FT-USAR-$subordinates',
      name: 'Fuerza de Tarea USAR',
      resourceClass: SciResourceClass.FUERZA_TAREA,
      resourceType: 1,
      category: SciResourceCategory.RESCATE_URBANO,
      status: SciResourceStatus.DISPONIBLE,
      supervisor: 'Líder Rama Rescate',
      subordinatesCount: subordinates,
      lat: 20.140,
      lon: -101.180,
    );
    setState(() {
      _lastSpanStatus = result.spanOfControl;
      _feedback = result.spanOfControl.message;
    });
  }

  Future<void> _reportRoadBlock() async {
    final entry = await widget.controller.submitQuickRoadBlock(
      lat: 20.1408,
      lon: -101.1803,
      severity: 9,
      hazardDescription: 'Puente colapsado / ruta bloqueada',
    );
    setState(() {
      _feedback = 'Bloqueo vial reportado (${entry.compactId})';
    });
  }

  void _generateCommandTransferQr() {
    final qr = widget.controller.createCommandTransferQr(
      incidentName: 'Operación Zona Cero',
      outgoingCommander: 'Cmdte. Saliente',
      incomingCommander: 'Cmdte. Entrante',
      situationDigest: 'Control de perímetro y recursos SCI-211 transferidos',
    );
    setState(() {
      _lastQrPayload = qr;
      _feedback = 'Código QR de Transferencia de Mando (CU-G05) generado';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(StgOledThemeSpec.backgroundHex),
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          const Text(
            'FORMULARIOS TÁCTICOS SCI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (_lastSpanStatus != null && _lastSpanStatus!.requiresAlert)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(StgOledThemeSpec.startRojoHex),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _lastSpanStatus!.message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          _GloveActionButton(
            title: 'SCI-201 · ASUMIR MANDO E INSTALACIONES (PC, E, ACV)',
            color: const Color(StgOledThemeSpec.sciPcOrangeHex),
            textColor: Colors.black,
            onPressed: _sendQuickSci201,
          ),
          const SizedBox(height: 12),
          _GloveActionButton(
            title: 'SCI-211 · CHECK-IN RECURSO (ALCANCE ÓPTIMO: 5)',
            color: const Color(StgOledThemeSpec.startVerdeHex),
            textColor: Colors.black,
            onPressed: () => _checkInResource(5),
          ),
          const SizedBox(height: 12),
          _GloveActionButton(
            title: 'SCI-211 · SIMULAR SOBRECARGA (CU-G03 > 7 SUBORDINADOS)',
            color: const Color(StgOledThemeSpec.startAmarilloHex),
            textColor: Colors.black,
            onPressed: () => _checkInResource(9),
          ),
          const SizedBox(height: 12),
          _GloveActionButton(
            title: 'REPORTAR BLOQUEO VIAL / PELIGRO EN RUTA',
            color: const Color(StgOledThemeSpec.startRojoHex),
            textColor: Colors.white,
            onPressed: _reportRoadBlock,
          ),
          const SizedBox(height: 12),
          _GloveActionButton(
            title: 'CU-G05 · TRANSFERENCIA DE MANDO DIGITAL (QR / BLE)',
            color: Colors.white,
            textColor: Colors.black,
            onPressed: _generateCommandTransferQr,
          ),
          if (_lastQrPayload != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(StgOledThemeSpec.surfaceHex),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white54),
              ),
              child: SelectableText(
                'QR CU-G05: $_lastQrPayload',
                style: const TextStyle(color: Colors.greenAccent, fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            _feedback,
            style: const TextStyle(color: Colors.amberAccent, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _GloveActionButton extends StatelessWidget {
  final String title;
  final Color color;
  final Color textColor;
  final VoidCallback onPressed;

  const _GloveActionButton({
    required this.title,
    required this.color,
    required this.textColor,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: StgOledThemeSpec.minGloveButtonHeightDp,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: textColor,
          ),
        ),
      ),
    );
  }
}
