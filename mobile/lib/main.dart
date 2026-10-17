import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'binary_frame.dart';

const String kApiBase = 'http://127.0.0.1:8000';

void main() => runApp(const BrigadistaApp());

class BrigadistaApp extends StatelessWidget {
  const BrigadistaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STG-AA · Terminal Táctica Brigadista',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F6F3),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111111)),
        useMaterial3: true,
      ),
      home: const BrigadistaHomeScreen(),
    );
  }
}

class BrigadistaHomeScreen extends StatefulWidget {
  const BrigadistaHomeScreen({super.key});

  @override
  State<BrigadistaHomeScreen> createState() => _BrigadistaHomeScreenState();
}

class _BrigadistaHomeScreenState extends State<BrigadistaHomeScreen> {
  int _tabIndex = 0;
  int _seq = 1;
  String _statusBanner = 'ENLACE BLE ACTIVO · NODO #901 · 915 MHz';

  // Tab 1: Triaje START (SCI-207) y Gravedad (SCI-201)
  String _selectedZone = '20.1355,-101.1845,Zona 02 · Sector Sur';
  int _incidentKind = 0;
  int _rojo = 2, _amarillo = 2, _verde = 1, _negro = 0;
  double _severity = 9;
  final Set<String> _hazards = {'Riesgo de colapso'};

  // Tab 2: Bloqueos Viales
  String _streetPreset = 'Av. Hidalgo Norte,20.1432,-101.1772';
  String _blockCause = 'Escombros / Derrumbe';
  String _blockClosure = 'Cierre total';
  final List<String> _reportedBlocks = [];

  // Tab 3: Recursos (SCI-211)
  String _resZone = 'Zona 02 · Sector Sur';
  String _resType = 'Fuerza de Tarea USAR / BREC';
  String _resStatus = 'Solicitado urgente en escena';
  final TextEditingController _resNotesCtrl =
      TextEditingController(text: 'Se requiere equipo hidráulico de corte');
  final List<String> _reportedResources = [];

  Future<void> _sendTriageAndSeverity() async {
    final parts = _selectedZone.split(',');
    final lat = double.parse(parts[0]);
    final lon = double.parse(parts[1]);
    final zoneName = parts[2];
    final total = (_rojo + _amarillo + _verde + _negro).clamp(1, 999);

    final frame = StgFrame(
      kind: _incidentKind,
      seq: _seq++,
      nodeTime: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      lat: lat,
      lon: lon,
      severity: _severity.round(),
      affected: total,
    );
    final hex = frame.encodeHex();

    setState(() => _statusBanner = 'Transmitiendo trama 25B: $hex');
    try {
      await http.post(
        Uri.parse('$kApiBase/ingest/frame'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'hex': hex}),
      );
      if (_hazards.isNotEmpty) {
        await http.post(
          Uri.parse('$kApiBase/field/resource'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'zone': zoneName,
            'resource': 'Alerta de Peligro SCI-201 (Sev ${_severity.round()}/10)',
            'unit_status': 'Perímetro activo',
            'notes': _hazards.join(', '),
          }),
        );
      }
      setState(() => _statusBanner = 'CONFIRMADO EN PC · Trama 25B: $hex');
    } catch (_) {
      setState(() => _statusBanner = 'ENCOLADO EN BLE · Trama 25B: $hex');
    }
  }

  Future<void> _sendRoadblock() async {
    final parts = _streetPreset.split(',');
    final street = parts[0];
    final lat = double.parse(parts[1]);
    final lon = double.parse(parts[2]);

    try {
      await http.post(
        Uri.parse('$kApiBase/field/roadblock'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'street': street,
          'cause': _blockCause,
          'closure': _blockClosure,
          'lat': lat,
          'lon': lon,
        }),
      );
      setState(() {
        _reportedBlocks.insert(0, '$street · $_blockCause ($_blockClosure)');
        _statusBanner = 'BLOQUEO VIAL SINCRONIZADO EN MAPA DEL PC: $street';
      });
    } catch (_) {
      setState(() => _statusBanner = 'Error al enviar bloqueo vial.');
    }
  }

  Future<void> _sendResource() async {
    try {
      await http.post(
        Uri.parse('$kApiBase/field/resource'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'zone': _resZone,
          'resource': _resType,
          'unit_status': _resStatus,
          'notes': _resNotesCtrl.text.trim(),
        }),
      );
      setState(() {
        _reportedResources.insert(0, '$_resType → $_resZone ($_resStatus)');
        _statusBanner = 'REPORTE SCI-211 RECIBIDO POR EL PUESTO DE COMANDO';
      });
    } catch (_) {
      setState(() => _statusBanner = 'Error al enviar solicitud SCI-211.');
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
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          Text(sub, style: const TextStyle(color: Colors.black54, fontSize: 11)),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => onDelta(-1), icon: const Icon(Icons.remove, size: 18)),
              Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              IconButton(onPressed: () => onDelta(1), icon: const Icon(Icons.add, size: 18)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTriageTab() {
    const hazardOptions = [
      'Riesgo de colapso',
      'Fuga de gas',
      'Cables eléctricos',
      'Acceso reducido',
    ];
    return ListView(
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
            DropdownMenuItem(
              value: '20.1355,-101.1845,Zona 02 · Sector Sur',
              child: Text('Zona 02 · Sector Sur (Sin verificar)'),
            ),
            DropdownMenuItem(
              value: '20.1475,-101.1710,Zona 03 · Sector Oriente',
              child: Text('Zona 03 · Sector Oriente (Sin verificar)'),
            ),
            DropdownMenuItem(
              value: '20.1410,-101.1790,Zona 01 · Centro',
              child: Text('Zona 01 · Centro (Actualizar)'),
            ),
          ],
          onChanged: (v) => setState(() => _selectedZone = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _incidentKind,
          decoration: const InputDecoration(
            labelText: '2. Naturaleza del incidente (SCI-201)',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 0, child: Text('Derrumbe estructural')),
            DropdownMenuItem(value: 1, child: Text('Personas atrapadas')),
            DropdownMenuItem(value: 2, child: Text('Inundación severa')),
            DropdownMenuItem(value: 3, child: Text('Incendio / Material peligroso')),
            DropdownMenuItem(value: 4, child: Text('Múltiples heridos graves')),
          ],
          onChanged: (v) => setState(() => _incidentKind = v!),
        ),
        const SizedBox(height: 14),
        const Text('3. Clasificación de víctimas · Triaje START (SCI-207)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.4,
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
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('4. Gravedad evaluada en escena', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('${_severity.round()} / 10',
                      style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFB91C1C), fontSize: 16)),
                ],
              ),
              Slider(
                value: _severity,
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: const Color(0xFFB91C1C),
                onChanged: (v) => setState(() => _severity = v),
              ),
              const Text('Amenazas en el perímetro de seguridad:',
                  style: TextStyle(fontSize: 12, color: Colors.black54)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: hazardOptions.map((h) {
                  final selected = _hazards.contains(h);
                  return FilterChip(
                    label: Text(h, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    onSelected: (val) => setState(() => val ? _hazards.add(h) : _hazards.remove(h)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111111)),
            onPressed: _sendTriageAndSeverity,
            child: const Text('Transmitir dictamen verificado (Trama 25B · LoRa)'),
          ),
        ),
      ],
    );
  }

  Widget _buildRoadblocksTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('REPORTE DE VIALIDADES CERRADAS O COLAPSADAS',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _streetPreset,
          decoration: const InputDecoration(
            labelText: '1. Vialidad o cruce afectado',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Av. Hidalgo Norte,20.1432,-101.1772', child: Text('Av. Hidalgo Norte (Acceso Centro)')),
            DropdownMenuItem(value: 'Puente Río Moroleón,20.1372,-101.1830', child: Text('Puente Río Moroleón (Ruta Sur)')),
            DropdownMenuItem(value: 'Blvd. Leovino Zavala,20.1455,-101.1735', child: Text('Blvd. Leovino Zavala (Ruta Oriente)')),
            DropdownMenuItem(value: 'Calle 16 de Septiembre,20.1398,-101.1804', child: Text('Calle 16 de Septiembre')),
          ],
          onChanged: (v) => setState(() => _streetPreset = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _blockCause,
          decoration: const InputDecoration(
            labelText: '2. Causa de la obstrucción',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Escombros / Derrumbe', child: Text('Escombros / Derrumbe estructural')),
            DropdownMenuItem(value: 'Inundación / Corriente', child: Text('Inundación / Corriente de agua')),
            DropdownMenuItem(value: 'Cables de alta tensión', child: Text('Poste o cables de alta tensión caídos')),
            DropdownMenuItem(value: 'Fractura de vía / Socavón', child: Text('Fractura de vía / Socavón')),
          ],
          onChanged: (v) => setState(() => _blockCause = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _blockClosure,
          decoration: const InputDecoration(
            labelText: '3. Nivel de bloqueo',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Cierre total', child: Text('Cierre total (Rutas de ambulancia bloqueadas)')),
            DropdownMenuItem(value: 'Solo unidades ligeras', child: Text('Paso restringido solo a unidades ligeras')),
          ],
          onChanged: (v) => setState(() => _blockClosure = v!),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB91C1C)),
            onPressed: _sendRoadblock,
            child: const Text('Marcar bloqueo vial en mapa del Puesto de Comando'),
          ),
        ),
        const SizedBox(height: 16),
        if (_reportedBlocks.isNotEmpty) ...[
          const Text('Bloqueos reportados en esta sesión:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ..._reportedBlocks.map((b) => Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  dense: true,
                  title: Text(b, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              )),
        ],
      ],
    );
  }

  Widget _buildResourcesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('SOLICITUD Y ESTADO DE RECURSOS (FORMULARIO SCI-211)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _resZone,
          decoration: const InputDecoration(
            labelText: '1. Zona o instalación SCI solicitante',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Zona 02 · Sector Sur', child: Text('Zona 02 · Sector Sur (ACV Sur)')),
            DropdownMenuItem(value: 'Zona 03 · Sector Oriente', child: Text('Zona 03 · Sector Oriente')),
            DropdownMenuItem(value: 'Zona 01 · Centro', child: Text('Zona 01 · Centro (ACV Principal)')),
            DropdownMenuItem(value: 'Área de Espera (E)', child: Text('Área de Espera (E)')),
          ],
          onChanged: (v) => setState(() => _resZone = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _resType,
          decoration: const InputDecoration(
            labelText: '2. Clase y tipo de recurso requerido',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Fuerza de Tarea USAR / BREC', child: Text('Fuerza de Tarea USAR / BREC (Búsqueda y Rescate)')),
            DropdownMenuItem(value: 'Ambulancia Soporte Vital (Tipo I)', child: Text('Ambulancia Soporte Vital Avanzado (Tipo I)')),
            DropdownMenuItem(value: 'Camión Motobomba Extinción', child: Text('Camión Motobomba de Extinción')),
            DropdownMenuItem(value: 'Maquinaria Pesada / Retroexcavadora', child: Text('Maquinaria Pesada / Remoción de Escombros')),
          ],
          onChanged: (v) => setState(() => _resType = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _resStatus,
          decoration: const InputDecoration(
            labelText: '3. Condición de estado SCI-211',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 'Solicitado urgente en escena', child: Text('Solicitado urgente en escena')),
            DropdownMenuItem(value: 'Asignado trabajando en escena', child: Text('Asignado (Trabajando en escena)')),
            DropdownMenuItem(value: 'Disponible en Área de Espera (E)', child: Text('Disponible en Área de Espera (E)')),
            DropdownMenuItem(value: 'No disponible (Relevo/Mantenimiento)', child: Text('No disponible (Relevo / Mantenimiento)')),
          ],
          onChanged: (v) => setState(() => _resStatus = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _resNotesCtrl,
          decoration: const InputDecoration(
            labelText: '4. Observaciones tácticas / equipamiento específico',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 50,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF111111)),
            onPressed: _sendResource,
            child: const Text('Transmitir reporte de recursos SCI-211'),
          ),
        ),
        const SizedBox(height: 16),
        if (_reportedResources.isNotEmpty) ...[
          const Text('Movimientos SCI-211 transmitidos:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ..._reportedResources.map((r) => Card(
                color: Colors.white,
                elevation: 0,
                child: ListTile(
                  dense: true,
                  title: Text(r, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              )),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildTriageTab(),
      _buildRoadblocksTab(),
      _buildResourcesTab(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('STG-AA · Terminal Táctica de Brigadista',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            Text('Sistema de Comando de Incidentes (SCI-201 / 207 / 211)',
                style: TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF111111),
                child: Text(
                  _statusBanner,
                  style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
                ),
              ),
              Expanded(child: pages[_tabIndex]),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.medical_information_outlined),
            label: 'Triaje y Gravedad',
          ),
          NavigationDestination(
            icon: Icon(Icons.block),
            label: 'Bloqueos Viales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Recursos SCI-211',
          ),
        ],
      ),
    );
  }
}
