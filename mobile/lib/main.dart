import 'package:flutter/material.dart';

import 'core/app_coordinator.dart';
import 'core/theme/oled_theme.dart';
import 'features/formularios_sci/sci_forms_screen.dart';
import 'features/mapa_offline/offline_map_screen.dart';
import 'features/triaje/start_triage_screen.dart';

export 'core/app_coordinator.dart';

void main() {
  final coordinator = StgTacticalMobileApp.wired(nodeId: 100);
  runApp(StgBrigadistaFlutterApp(coordinator: coordinator));
}

/// Aplicación Flutter Táctica Offline-First para Brigadistas (STG-AA).
/// Tema nativo OLED Black (#000000), botones >= 64x64 dp para guantes y flujo en <= 3 toques.
class StgBrigadistaFlutterApp extends StatefulWidget {
  final StgTacticalMobileApp coordinator;

  const StgBrigadistaFlutterApp({Key? key, required this.coordinator})
      : super(key: key);

  @override
  State<StgBrigadistaFlutterApp> createState() =>
      _StgBrigadistaFlutterAppState();
}

class _StgBrigadistaFlutterAppState extends State<StgBrigadistaFlutterApp> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final c = widget.coordinator;
    final screens = [
      StartTriageScreen(controller: c.startTriage),
      SciFormsScreen(controller: c.sciForms),
      OfflineMapScreen(mapController: c.offlineMap, store: c.store),
    ];

    return MaterialApp(
      title: 'STG-AA Brigadista SCI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(StgOledThemeSpec.backgroundHex),
        canvasColor: const Color(StgOledThemeSpec.backgroundHex),
      ),
      home: Scaffold(
        backgroundColor: const Color(StgOledThemeSpec.backgroundHex),
        appBar: AppBar(
          backgroundColor: const Color(StgOledThemeSpec.surfaceHex),
          title: const Text(
            'STG-AA · TERMINAL TÁCTICA SCI',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  'BLE: ${c.bleService.status.name} | ACK: ${c.store.ackedCount}/${c.store.outboxEntries.length}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: const Color(StgOledThemeSpec.surfaceHex),
          selectedItemColor: const Color(StgOledThemeSpec.sciPcOrangeHex),
          unselectedItemColor: Colors.white70,
          currentIndex: _selectedIndex,
          onTap: (idx) => setState(() => _selectedIndex = idx),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.medical_services, size: 30),
              label: 'Triaje START (207)',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_turned_in, size: 30),
              label: 'SCI 201 / 211',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map, size: 30),
              label: 'Mapa Offline',
            ),
          ],
        ),
      ),
    );
  }
}
