import '../../core/database/local_store.dart';
import '../../core/theme/oled_theme.dart';
import '../../core/voice/offline_voice_service.dart';
import '../../services/ble_service.dart';
import 'sci_models.dart';

class Sci211RegistrationResult {
  final Sci211Resource resource;
  final SpanOfControlStatus spanOfControl;

  const Sci211RegistrationResult({
    required this.resource,
    required this.spanOfControl,
  });
}

/// Controlador de formularios tácticos SCI-201, SCI-211, Bloqueos Viales,
/// Alerta de Alcance de Control (CU-G03) y Transferencia de Mando QR/BLE (CU-G05).
/// Diseñado bajo la regla de máximo 3 toques y botones >= 64x64 dp.
class SciFormsController {
  final OfflineTacticalStore store;
  final StgBleService bleService;
  final OfflineVoiceDictationService voiceService;

  SciFormsController({
    required this.store,
    required this.bleService,
    required this.voiceService,
  });

  double get minButtonHeightDp => StgOledThemeSpec.minGloveButtonHeightDp;

  /// Flujo en <= 3 toques para registrar SCI-201 con instalaciones (PC, E, ACV, B, C, H1)
  Future<OutboxEntry> submitQuickSci201({
    required String incidentName,
    required String commanderName,
    required int kind,
    required int severity,
    required List<SciFacility> facilities,
    required List<GeoPoint> securityPerimeter,
    required String situationSummary,
  }) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final report = Sci201Report(
      compactId: store.nextCompactId('201'),
      incidentName: incidentName,
      commanderName: commanderName,
      kind: kind,
      severity: severity,
      securityPerimeter: securityPerimeter,
      facilities: facilities,
      situationSummary: situationSummary,
      createdAtSec: nowSec,
    );
    final entry = store.saveSci201(report);
    await bleService.flushOutboxQueue();
    return entry;
  }

  /// Registro de recursos SCI-211 y evaluación inmediata de Alcance de Control (CU-G03: 3..7, óptimo 5)
  Sci211RegistrationResult registerSci211AndCheckSpan({
    required String code,
    required String name,
    required SciResourceClass resourceClass,
    required int resourceType,
    required SciResourceCategory category,
    required SciResourceStatus status,
    required String supervisor,
    required int subordinatesCount,
    required double lat,
    required double lon,
  }) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final res = Sci211Resource(
      compactId: store.nextCompactId('211'),
      code: code,
      name: name,
      resourceClass: resourceClass,
      resourceType: resourceType,
      category: category,
      status: status,
      supervisor: supervisor,
      subordinatesCount: subordinatesCount,
      lat: lat,
      lon: lon,
      updatedAtSec: nowSec,
    );
    store.upsertSci211Resource(res);
    final span = SpanOfControlStatus.evaluate(supervisor, subordinatesCount);
    return Sci211RegistrationResult(resource: res, spanOfControl: span);
  }

  /// Flujo de 3 toques para reportar un bloqueo vial georreferenciado
  Future<OutboxEntry> submitQuickRoadBlock({
    required double lat,
    required double lon,
    required int severity,
    required String hazardDescription,
    double radiusMeters = 60.0,
  }) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final report = RoadBlockReport(
      compactId: store.nextCompactId('RB'),
      lat: lat,
      lon: lon,
      severity: severity,
      radiusMeters: radiusMeters,
      hazardDescription: hazardDescription,
      createdAtSec: nowSec,
    );
    final entry = store.saveRoadBlock(report);
    await bleService.flushOutboxQueue();
    return entry;
  }

  /// CU-G05: Genera y registra la transferencia de mando cara a cara (QR / BLE)
  String createCommandTransferQr({
    required String incidentName,
    required String outgoingCommander,
    required String incomingCommander,
    required String situationDigest,
  }) {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final payload = CommandTransferPayload(
      compactId: store.nextCompactId('CMD'),
      incidentName: incidentName,
      outgoingCommander: outgoingCommander,
      incomingCommander: incomingCommander,
      situationDigest: situationDigest,
      activeResources: store.sci211Resources.length,
      timestampSec: nowSec,
    );
    store.recordCommandTransfer(payload);
    return payload.toQrPayload();
  }
}
