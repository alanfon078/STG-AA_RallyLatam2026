import 'dart:math' as math;
import '../../core/protocol/binary_frame.dart';

/// Categorías de Triaje START en el Área de Concentración de Víctimas (ACV) - SCI-207
enum StartColor {
  ROJO, // Prioridad 1: Atención / evacuación inmediata (riesgo vital inminente)
  AMARILLO, // Prioridad 2: Atención demorada (lesiones graves pero estables)
  VERDE, // Prioridad 3: Leves / ambulatorios ("heridos que caminan")
  NEGRO, // Fallecido / sin respiración tras apertura de vía aérea
}

class StartVictimEntry {
  final String compactId;
  final StartColor color;
  final String tagCode;
  final String conditionNote;
  final String destinationHospital;
  final int registeredAtSec;

  const StartVictimEntry({
    required this.compactId,
    required this.color,
    required this.tagCode,
    this.conditionNote = '',
    this.destinationHospital = '',
    required this.registeredAtSec,
  });

  Map<String, dynamic> toMap() => {
        'compact_id': compactId,
        'color': color.name,
        'tag_code': tagCode,
        'condition_note': conditionNote,
        'destination_hospital': destinationHospital,
        'registered_at_sec': registeredAtSec,
      };
}

/// Consolidado SCI-207 en el ACV con conversión a trama binaria verificada
class StartTriageSummary {
  final String compactId;
  final String acvName;
  final double lat;
  final double lon;
  final int rojoCount;
  final int amarilloCount;
  final int verdeCount;
  final int negroCount;
  final List<StartVictimEntry> victims;
  final int updatedAtSec;

  const StartTriageSummary({
    required this.compactId,
    required this.acvName,
    required this.lat,
    required this.lon,
    this.rojoCount = 0,
    this.amarilloCount = 0,
    this.verdeCount = 0,
    this.negroCount = 0,
    this.victims = const [],
    required this.updatedAtSec,
  });

  int get totalVictims => rojoCount + amarilloCount + verdeCount + negroCount;

  /// Calcula la severidad táctica (0..10) priorizando víctimas ROJO y AMARILLO
  int get calculatedSeverity {
    if (totalVictims == 0) return 0;
    if (rojoCount >= 3) return 10;
    if (rojoCount == 2) return 9;
    if (rojoCount == 1) return math.min(10, 8 + (amarilloCount >= 2 ? 1 : 0));
    if (amarilloCount >= 3) return 7;
    if (amarilloCount >= 1) return 6;
    if (negroCount >= 1) return 5;
    return math.min(4, math.max(1, verdeCount));
  }

  /// Convierte el dictamen SCI-207 en una trama binaria verificada de 25 bytes
  StgFrame toBinaryFrame({required int nodeId, required int seq}) {
    final kind = rojoCount > 0 ? 4 : 1; // 4 = HERIDO_GRAVE, 1 = PERSONA_ATRAPADA
    return StgFrame(
      flags: StgFrame.flagBrigadista | StgFrame.flagPriority,
      kind: kind,
      nodeId: nodeId,
      seq: seq,
      nodeTime: updatedAtSec,
      lat: lat,
      lon: lon,
      severity: calculatedSeverity,
      affected: totalVictims,
    );
  }

  Map<String, dynamic> toMap() => {
        'compact_id': compactId,
        'acv_name': acvName,
        'lat': lat,
        'lon': lon,
        'rojo_count': rojoCount,
        'amarillo_count': amarilloCount,
        'verde_count': verdeCount,
        'negro_count': negroCount,
        'severity': calculatedSeverity,
        'updated_at_sec': updatedAtSec,
      };
}
