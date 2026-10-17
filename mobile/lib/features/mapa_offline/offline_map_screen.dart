import 'package:flutter/material.dart';

import '../../core/database/local_store.dart';
import '../../core/theme/oled_theme.dart';
import 'offline_map_service.dart';

/// Pantalla Flutter de Cartografía Vectorial Offline (MBTiles / PMTiles locales)
/// con visualización de clústeres, simbología normada SCI (PC, E, ACV, B, C, H1) y bloqueos viales.
class OfflineMapScreen extends StatelessWidget {
  final OfflineCartographyController mapController;
  final OfflineTacticalStore store;

  const OfflineMapScreen({
    Key? key,
    required this.mapController,
    required this.store,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pins = mapController.buildTacticalOverlay(
      sci201Reports: store.sci201Reports,
      roadBlocks: store.roadBlocks,
    );

    return Container(
      color: const Color(StgOledThemeSpec.backgroundHex),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'MAPA TÁCTICO OFFLINE (MBTiles / PMTiles)',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Fuente local: ${mapController.mbtilesAssetPath}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: pins.isEmpty
                ? const Center(
                    child: Text(
                      'Sin pines tácticos aún. Registre SCI-201 o un bloqueo vial.',
                      style: TextStyle(color: Colors.white54, fontSize: 16),
                    ),
                  )
                : ListView.separated(
                    itemCount: pins.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final p = pins[index];
                      final isBlock = p.category == 'ROADBLOCK';
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(StgOledThemeSpec.surfaceHex),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isBlock
                                ? const Color(StgOledThemeSpec.startRojoHex)
                                : const Color(StgOledThemeSpec.sciPcOrangeHex),
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isBlock
                                    ? const Color(StgOledThemeSpec.startRojoHex)
                                    : const Color(
                                        StgOledThemeSpec.sciPcOrangeHex),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                p.symbolCode,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '(${p.lat.toStringAsFixed(5)}, ${p.lon.toStringAsFixed(5)})',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
