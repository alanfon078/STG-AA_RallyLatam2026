import 'dart:convert';
import '../../core/protocol/binary_frame.dart';

/// Simbología normada SCI para instalaciones tácticas (SCI-201)
enum SciFacilityType {
  PC, // Puesto de Comando (Rectángulo naranja)
  E, // Área de Espera (Círculo amarillo con letra E)
  ACV, // Área de Concentración de Víctimas (Círculo con letras ACV)
  B, // Base
  C, // Campamento
  H1, // Helipunto
}

class GeoPoint {
  final double lat;
  final double lon;
  const GeoPoint(this.lat, this.lon);

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};
  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        (json['lat'] as num).toDouble(),
        (json['lon'] as num).toDouble(),
      );
}

class SciFacility {
  final SciFacilityType type;
  final GeoPoint location;
  final String label;

  const SciFacility({
    required this.type,
    required this.location,
    this.label = '',
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'lat': location.lat,
        'lon': location.lon,
        'label': label,
      };
}

/// Formulario SCI-201: Resumen del Incidente, Asunción de Mando, Perímetro e Instalaciones
class Sci201Report {
  final String compactId;
  final String incidentName;
  final String commanderName;
  final int kind; // 0..4
  final int severity; // 0..10
  final List<GeoPoint> securityPerimeter;
  final List<SciFacility> facilities;
  final String situationSummary;
  final String safetyMessage;
  final int createdAtSec;

  const Sci201Report({
    required this.compactId,
    required this.incidentName,
    required this.commanderName,
    required this.kind,
    required this.severity,
    required this.securityPerimeter,
    required this.facilities,
    required this.situationSummary,
    this.safetyMessage = '',
    required this.createdAtSec,
  });

  GeoPoint get primaryPoint {
    for (final f in facilities) {
      if (f.type == SciFacilityType.PC) return f.location;
    }
    if (facilities.isNotEmpty) return facilities.first.location;
    if (securityPerimeter.isNotEmpty) return securityPerimeter.first;
    return const GeoPoint(20.140, -101.180);
  }

  StgFrame toBinaryFrame({required int nodeId, required int seq}) {
    final pt = primaryPoint;
    return StgFrame(
      flags: StgFrame.flagBrigadista | StgFrame.flagPriority,
      kind: kind,
      nodeId: nodeId,
      seq: seq,
      nodeTime: createdAtSec,
      lat: pt.lat,
      lon: pt.lon,
      severity: severity,
      affected: facilities.length,
    );
  }

  Map<String, dynamic> toMap() => {
        'compact_id': compactId,
        'incident_name': incidentName,
        'commander_name': commanderName,
        'kind': kind,
        'severity': severity,
        'perimeter_json':
            jsonEncode(securityPerimeter.map((p) => p.toJson()).toList()),
        'facilities_json':
            jsonEncode(facilities.map((f) => f.toJson()).toList()),
        'situation_summary': situationSummary,
        'safety_message': safetyMessage,
        'created_at_sec': createdAtSec,
      };
}

/// Clasificación SCI-211 de Recursos
enum SciResourceClass {
  RECURSO_SIMPLE,
  EQUIPO_INTERVENCION,
  FUERZA_TAREA,
}

enum SciResourceCategory {
  MEDICO,
  RESCATE_URBANO,
  BOMBEROS,
  RECONOCIMIENTO,
  MAQUINARIA_PESADA,
  SEGURIDAD,
  LOGISTICA,
}

enum SciResourceStatus {
  DISPONIBLE,
  ASIGNADO,
  NO_DISPONIBLE,
}

/// Formulario SCI-211: Registro y Check-in de Recursos
class Sci211Resource {
  final String compactId;
  final String code;
  final String name;
  final SciResourceClass resourceClass;
  final int resourceType; // 1 a 4
  final SciResourceCategory category;
  final SciResourceStatus status;
  final String supervisor;
  final int subordinatesCount;
  final double lat;
  final double lon;
  final int updatedAtSec;

  Sci211Resource({
    required this.compactId,
    required this.code,
    required this.name,
    required this.resourceClass,
    required this.resourceType,
    required this.category,
    required this.status,
    required this.supervisor,
    required this.subordinatesCount,
    required this.lat,
    required this.lon,
    required this.updatedAtSec,
  }) {
    if (resourceType < 1 || resourceType > 4) {
      throw ArgumentError('Tipo SCI-211 debe estar entre 1 y 4');
    }
  }

  Map<String, dynamic> toMap() => {
        'compact_id': compactId,
        'code': code,
        'name': name,
        'resource_class': resourceClass.name,
        'resource_type': resourceType,
        'category': category.name,
        'status': status.name,
        'supervisor': supervisor,
        'subordinates_count': subordinatesCount,
        'lat': lat,
        'lon': lon,
        'updated_at_sec': updatedAtSec,
      };
}

/// CU-G03: Evaluación de Alcance de Control SCI (3 a 7 subordinados, óptimo 5)
enum SpanOfControlLevel {
  OPTIMO, // Exactamente 5 subordinados
  DENTRO_DE_NORMA, // Entre 3 y 7 subordinados
  SUBUTILIZADO, // < 3 subordinados
  EXCEDIDO_CRITICO, // > 7 subordinados (requiere dividir sector/rama)
}

class SpanOfControlStatus {
  static const int minRecommended = 3;
  static const int maxAllowed = 7;
  static const int optimalTarget = 5;

  final String supervisor;
  final int subordinatesCount;
  final SpanOfControlLevel level;
  final String message;

  const SpanOfControlStatus({
    required this.supervisor,
    required this.subordinatesCount,
    required this.level,
    required this.message,
  });

  bool get requiresAlert => level == SpanOfControlLevel.EXCEDIDO_CRITICO;

  static SpanOfControlStatus evaluate(String supervisor, int count) {
    if (count > maxAllowed) {
      return SpanOfControlStatus(
        supervisor: supervisor,
        subordinatesCount: count,
        level: SpanOfControlLevel.EXCEDIDO_CRITICO,
        message:
            'ALERTA SCI CU-G03: $supervisor supervisa $count recursos (máximo normado: $maxAllowed, óptimo: $optimalTarget). Divida el sector o asigne otro líder.',
      );
    }
    if (count == optimalTarget) {
      return SpanOfControlStatus(
        supervisor: supervisor,
        subordinatesCount: count,
        level: SpanOfControlLevel.OPTIMO,
        message:
            'Alcance de control óptimo ($optimalTarget subordinados) para $supervisor.',
      );
    }
    if (count >= minRecommended) {
      return SpanOfControlStatus(
        supervisor: supervisor,
        subordinatesCount: count,
        level: SpanOfControlLevel.DENTRO_DE_NORMA,
        message:
            'Alcance de control en rango SCI ($count subordinados, rango 3–7).',
      );
    }
    return SpanOfControlStatus(
      supervisor: supervisor,
      subordinatesCount: count,
      level: SpanOfControlLevel.SUBUTILIZADO,
      message:
          'Baja carga ($count subordinados, mínimo sugerido $minRecommended).',
    );
  }
}

/// CU-G05: Transferencia de Mando Digital cara a cara (QR / Proximidad BLE)
class CommandTransferPayload {
  static const String prefix = 'STG-CMD-V1';

  final String compactId;
  final String incidentName;
  final String outgoingCommander;
  final String incomingCommander;
  final String situationDigest;
  final int activeResources;
  final int timestampSec;

  const CommandTransferPayload({
    required this.compactId,
    required this.incidentName,
    required this.outgoingCommander,
    required this.incomingCommander,
    required this.situationDigest,
    required this.activeResources,
    required this.timestampSec,
  });

  String toQrPayload() {
    final data = {
      'h': prefix,
      'id': compactId,
      'inc': incidentName,
      'out': outgoingCommander,
      'in': incomingCommander,
      'sum': situationDigest,
      'res': activeResources,
      'ts': timestampSec,
    };
    return jsonEncode(data);
  }

  factory CommandTransferPayload.fromQrPayload(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['h'] != prefix) {
      throw FormatException('Payload QR de transferencia SCI inválido');
    }
    return CommandTransferPayload(
      compactId: decoded['id'] as String,
      incidentName: decoded['inc'] as String,
      outgoingCommander: decoded['out'] as String,
      incomingCommander: decoded['in'] as String,
      situationDigest: decoded['sum'] as String,
      activeResources: (decoded['res'] as num).toInt(),
      timestampSec: (decoded['ts'] as num).toInt(),
    );
  }
}

/// Reporte rápido de bloqueo vial y peligro en ruta
class RoadBlockReport {
  final String compactId;
  final double lat;
  final double lon;
  final int severity; // 1..10
  final double radiusMeters;
  final String hazardDescription;
  final int createdAtSec;

  const RoadBlockReport({
    required this.compactId,
    required this.lat,
    required this.lon,
    required this.severity,
    this.radiusMeters = 60.0,
    required this.hazardDescription,
    required this.createdAtSec,
  });

  StgFrame toBinaryFrame({required int nodeId, required int seq}) {
    return StgFrame(
      flags: StgFrame.flagBrigadista | StgFrame.flagPriority,
      kind: 0, // DERRUMBE / Bloqueo estructural en ruta
      nodeId: nodeId,
      seq: seq,
      nodeTime: createdAtSec,
      lat: lat,
      lon: lon,
      severity: severity.clamp(1, 10),
      affected: 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'compact_id': compactId,
        'lat': lat,
        'lon': lon,
        'severity': severity,
        'radius_m': radiusMeters,
        'description': hazardDescription,
        'created_at_sec': createdAtSec,
      };
}
