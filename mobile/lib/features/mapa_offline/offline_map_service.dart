import '../formularios_sci/sci_models.dart';

class TacticalMapPin {
  final String id;
  final String category; // CLUSTER, SCI_FACILITY, ROADBLOCK
  final String symbolCode; // PC, E, ACV, B, C, H1, SOS, BLOCK
  final double lat;
  final double lon;
  final String title;

  const TacticalMapPin({
    required this.id,
    required this.category,
    required this.symbolCode,
    required this.lat,
    required this.lon,
    required this.title,
  });
}

/// Gestor de cartografía vectorial offline (MBTiles / PMTiles locales)
/// y capas tácticas (clústeres, instalaciones SCI y bloqueos viales).
class OfflineCartographyController {
  final String mbtilesAssetPath;
  final String pmtilesAssetPath;

  const OfflineCartographyController({
    this.mbtilesAssetPath = 'assets/maps/guanajuato_sur.mbtiles',
    this.pmtilesAssetPath = 'assets/maps/guanajuato_sur.pmtiles',
  });

  List<TacticalMapPin> buildTacticalOverlay({
    required List<Sci201Report> sci201Reports,
    required List<RoadBlockReport> roadBlocks,
  }) {
    final pins = <TacticalMapPin>[];

    for (final report in sci201Reports) {
      for (final facility in report.facilities) {
        pins.add(
          TacticalMapPin(
            id: '${report.compactId}-${facility.type.name}',
            category: 'SCI_FACILITY',
            symbolCode: facility.type.name,
            lat: facility.location.lat,
            lon: facility.location.lon,
            title: '${facility.type.name}: ${facility.label}',
          ),
        );
      }
    }

    for (final rb in roadBlocks) {
      pins.add(
        TacticalMapPin(
          id: rb.compactId,
          category: 'ROADBLOCK',
          symbolCode: 'BLOCK',
          lat: rb.lat,
          lon: rb.lon,
          title: 'Bloqueo (Sev ${rb.severity}): ${rb.hazardDescription}',
        ),
      );
    }

    return pins;
  }
}
