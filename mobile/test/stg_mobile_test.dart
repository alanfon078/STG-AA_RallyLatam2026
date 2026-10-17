import 'dart:convert';
import 'dart:typed_data';

import '../lib/core/app_coordinator.dart';
import '../lib/core/database/local_store.dart';
import '../lib/core/protocol/binary_frame.dart';
import '../lib/features/formularios_sci/sci_models.dart';
import '../lib/features/triaje/start_triage_model.dart';
import '../lib/services/ble_service.dart';

const String goldenHex = '010100038403070000f15365f84b3301402df8f90904004c78';

void expectEqual(Object? actual, Object? expected, String description) {
  if (actual != expected) {
    throw StateError('FALLO [$description]: esperado=$expected, actual=$actual');
  }
}

void expectTrue(bool condition, String description) {
  if (!condition) {
    throw StateError('FALLO [$description]: se esperaba true');
  }
}

Future<void> main() async {
  // 1. Verificar paridad binaria de 25 bytes con vector dorado de C++ y Python
  const golden = StgFrame(
    flags: StgFrame.flagBrigadista,
    kind: 0,
    nodeId: 900,
    seq: 7,
    nodeTime: 1700000000,
    lat: 20.139,
    lon: -101.176,
    severity: 9,
    affected: 4,
    ttl: 3,
  );
  expectEqual(golden.toHex(), goldenHex, 'Vector dorado 25 bytes Dart == C++/Python');
  final decoded = StgFrame.fromHex(goldenHex);
  expectTrue(decoded.verified, 'Bandera de brigadista verificada');
  expectEqual(decoded.nodeId, 900, 'Node ID decodificado');
  expectEqual(decoded.severity, 9, 'Severidad decodificada');

  // 2. Verificar tema OLED Black (#000000) y botones >= 60x60 dp para guantes
  final app = StgTacticalMobileApp.wired(nodeId: 100);
  expectEqual(app.backgroundColorHex, 0xFF000000, 'Tema oscuro OLED Black #000000');
  expectTrue(
    app.sciForms.minButtonHeightDp >= 60.0 &&
        app.startTriage.minButtonDimensionDp >= 60.0,
    'Botones >= 60x60 dp para uso con guantes',
  );

  // 3. Emparejar servicio BLE y probar SCI-201 con instalaciones (PC, E, ACV, B, C, H1)
  await app.bleService.pairWithDevice('STG-AA-NODO-100');
  expectEqual(
    app.bleService.status,
    BleConnectionStatus.CONNECTED,
    'Conexión BLE establecida con nodo portátil',
  );

  final sci201Entry = await app.sciForms.submitQuickSci201(
    incidentName: 'Colapso Sector Centro',
    commanderName: 'Cmdte. Fonseca',
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
          label: 'Puesto de Comando Central'),
      SciFacility(
          type: SciFacilityType.E,
          location: GeoPoint(20.1395, -101.1805),
          label: 'Área de Espera Sur'),
      SciFacility(
          type: SciFacilityType.ACV,
          location: GeoPoint(20.1402, -101.1798),
          label: 'ACV Principal'),
      SciFacility(
          type: SciFacilityType.B,
          location: GeoPoint(20.138, -101.182),
          label: 'Base Logística'),
      SciFacility(
          type: SciFacilityType.C,
          location: GeoPoint(20.137, -101.183),
          label: 'Campamento 1'),
      SciFacility(
          type: SciFacilityType.H1,
          location: GeoPoint(20.142, -101.177),
          label: 'Helipunto Deportivo'),
    ],
    situationSummary: 'Colapso parcial con víctimas atrapadas',
  );
  expectEqual(
    sci201Entry.state,
    OutboxSyncState.SENT,
    'SCI-201 encolado y enviado por BLE esperando ACK',
  );

  // Simular recepción de ACK desde el nodo LoRa vía BLE TX
  app.bleService.onRawNotificationReceived(
    Uint8List.fromList(utf8.encode('ACK:${sci201Entry.nodeId}:${sci201Entry.seq}')),
  );
  expectEqual(
    sci201Entry.state,
    OutboxSyncState.ACKED,
    'Confirmación de entrega ACK actualiza estado en cola local',
  );

  // 4. Probar SCI-211 y Alerta de Alcance de Control (CU-G03: 3..7, óptimo 5)
  final optimalSpan = app.sciForms.registerSci211AndCheckSpan(
    code: 'USAR-01',
    name: 'Brigada USAR 1',
    resourceClass: SciResourceClass.FUERZA_TAREA,
    resourceType: 1,
    category: SciResourceCategory.RESCATE_URBANO,
    status: SciResourceStatus.DISPONIBLE,
    supervisor: 'Tte. Nambo',
    subordinatesCount: 5,
    lat: 20.140,
    lon: -101.180,
  );
  expectEqual(
    optimalSpan.spanOfControl.level,
    SpanOfControlLevel.OPTIMO,
    'Alcance de control óptimo con 5 subordinados',
  );
  expectTrue(!optimalSpan.spanOfControl.requiresAlert, 'Sin alerta en óptimo 5');

  final overloadedSpan = app.sciForms.registerSci211AndCheckSpan(
    code: 'AMB-09',
    name: 'Unidad Médica 9',
    resourceClass: SciResourceClass.RECURSO_SIMPLE,
    resourceType: 2,
    category: SciResourceCategory.MEDICO,
    status: SciResourceStatus.ASIGNADO,
    supervisor: 'Jefe Sector Norte',
    subordinatesCount: 9,
    lat: 20.141,
    lon: -101.181,
  );
  expectTrue(
    overloadedSpan.spanOfControl.requiresAlert,
    'Alerta CU-G03 activada al superar 7 subordinados',
  );

  // 5. Probar SCI-207 Triaje START (Rojo, Amarillo, Verde, Negro) + Dictado por Voz Offline
  app.startTriage.incrementColor(StartColor.ROJO, conditionNote: 'Hemorragia severa');
  app.startTriage.applyVoiceDictation('dos rojos tres amarillos un verde');
  final sci207Entry = await app.startTriage.transmitAcvTriage(
    acvName: 'ACV Principal',
    lat: 20.1402,
    lon: -101.1798,
  );
  expectEqual(app.startTriage.rojoCount, 3, 'Conteo START Rojo (1 botón + 2 voz)');
  expectEqual(app.startTriage.amarilloCount, 3, 'Conteo START Amarillo por voz');
  expectEqual(app.startTriage.verdeCount, 1, 'Conteo START Verde por voz');
  expectEqual(sci207Entry.frame.severity, 10, 'Severidad máxima por >= 3 víctimas ROJO');
  expectTrue(sci207Entry.frame.verified, 'Trama SCI-207 lleva FLAG_BRIGADISTA');

  // 6. Probar reporte rápido de Bloqueo Vial y superposición en Mapa Offline
  final rbEntry = await app.sciForms.submitQuickRoadBlock(
    lat: 20.1405,
    lon: -101.1805,
    severity: 9,
    hazardDescription: 'Derrumbe bloquea calle Hidalgo',
  );
  expectEqual(rbEntry.formType, 'ROADBLOCK', 'Reporte de bloqueo vial generado');

  final mapPins = app.offlineMap.buildTacticalOverlay(
    sci201Reports: app.store.sci201Reports,
    roadBlocks: app.store.roadBlocks,
  );
  expectEqual(
    mapPins.length,
    7,
    '6 instalaciones SCI (PC, E, ACV, B, C, H1) + 1 bloqueo vial en mapa offline',
  );

  // 7. Probar Transferencia de Mando Digital QR/BLE (CU-G05)
  final qrString = app.sciForms.createCommandTransferQr(
    incidentName: 'Colapso Sector Centro',
    outgoingCommander: 'Cmdte. Fonseca',
    incomingCommander: 'Cmdte. Tenorio',
    situationDigest: 'Perímetro asegurado, ACV operando con 7 víctimas',
  );
  final parsedTransfer = CommandTransferPayload.fromQrPayload(qrString);
  expectEqual(
    parsedTransfer.incomingCommander,
    'Cmdte. Tenorio',
    'Transferencia de mando QR decodificada íntegramente (CU-G05)',
  );

  // 8. Probar recepción de orden descendente (Downlink: Puesto de Comando -> LoRa -> BLE)
  app.bleService.onRawNotificationReceived(golden.encode());
  expectEqual(
    app.store.downlinkFrames.length,
    1,
    'Trama descendente recibida desde el Puesto de Comando vía BLE',
  );

  await app.bleService.dispose();
  app.store.dispose();
  print('OK: Todas las pruebas de STG-AA Mobile (Feature 4) pasaron exitosamente.');
}
