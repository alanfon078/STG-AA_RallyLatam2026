import '../../core/database/local_store.dart';
import '../../core/theme/oled_theme.dart';
import '../../core/voice/offline_voice_service.dart';
import '../../services/ble_service.dart';
import 'start_triage_model.dart';

/// Controlador de Triaje Médico START (SCI-207) en el Área de Concentración de Víctimas (ACV).
/// Soporta incremento rápido en <= 3 toques con botones >= 64x64 dp y dictado por voz offline.
class StartTriageController {
  final OfflineTacticalStore store;
  final StgBleService bleService;
  final OfflineVoiceDictationService voiceService;

  int rojoCount = 0;
  int amarilloCount = 0;
  int verdeCount = 0;
  int negroCount = 0;
  final List<StartVictimEntry> victims = [];

  StartTriageController({
    required this.store,
    required this.bleService,
    required this.voiceService,
  });

  double get minButtonDimensionDp => StgOledThemeSpec.minGloveButtonHeightDp;

  void incrementColor(StartColor color, {String conditionNote = ''}) {
    switch (color) {
      case StartColor.ROJO:
        rojoCount++;
        break;
      case StartColor.AMARILLO:
        amarilloCount++;
        break;
      case StartColor.VERDE:
        verdeCount++;
        break;
      case StartColor.NEGRO:
        negroCount++;
        break;
    }
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    victims.add(
      StartVictimEntry(
        compactId: store.nextCompactId('V'),
        color: color,
        tagCode: '${color.name.substring(0, 1)}-${victims.length + 1}',
        conditionNote: conditionNote,
        registeredAtSec: nowSec,
      ),
    );
  }

  void applyVoiceDictation(String spokenText) {
    final transcript = voiceService.simulateTranscript(spokenText);
    final counts = voiceService.parseSpokenStartCounts(transcript);
    rojoCount += counts['ROJO'] ?? 0;
    amarilloCount += counts['AMARILLO'] ?? 0;
    verdeCount += counts['VERDE'] ?? 0;
    negroCount += counts['NEGRO'] ?? 0;
  }

  Future<OutboxEntry> transmitAcvTriage({
    required String acvName,
    required double lat,
    required double lon,
  }) async {
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final summary = StartTriageSummary(
      compactId: store.nextCompactId('207'),
      acvName: acvName,
      lat: lat,
      lon: lon,
      rojoCount: rojoCount,
      amarilloCount: amarilloCount,
      verdeCount: verdeCount,
      negroCount: negroCount,
      victims: List.unmodifiable(victims),
      updatedAtSec: nowSec,
    );
    final entry = store.saveSci207Triage(summary);
    await bleService.flushOutboxQueue();
    return entry;
  }
}
