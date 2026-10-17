import 'core/database/local_store.dart';
import 'core/theme/oled_theme.dart';
import 'core/voice/offline_voice_service.dart';
import 'features/formularios_sci/sci_forms_screen.dart';
import 'features/mapa_offline/offline_map_service.dart';
import 'features/triaje/start_triage_screen.dart';
import 'services/ble_service.dart';

/// Coordinador raíz de la Terminal Táctica STG-AA para Brigadistas (Architecture Feature-First).
class StgTacticalMobileApp {
  final OfflineTacticalStore store;
  final StgBleService bleService;
  final OfflineVoiceDictationService voiceService;
  final SciFormsController sciForms;
  final StartTriageController startTriage;
  final OfflineCartographyController offlineMap;

  StgTacticalMobileApp({int nodeId = 100, BleTransportAdapter? bleAdapter})
      : store = OfflineTacticalStore(nodeId: nodeId),
        voiceService = OfflineVoiceDictationService(),
        offlineMap = const OfflineCartographyController(),
        bleService = StgBleService(
          store: OfflineTacticalStore(nodeId: nodeId),
          adapter: bleAdapter,
        ),
        sciForms = SciFormsController(
          store: OfflineTacticalStore(nodeId: nodeId),
          bleService: StgBleService(store: OfflineTacticalStore(nodeId: nodeId)),
          voiceService: OfflineVoiceDictationService(),
        ),
        startTriage = StartTriageController(
          store: OfflineTacticalStore(nodeId: nodeId),
          bleService: StgBleService(store: OfflineTacticalStore(nodeId: nodeId)),
          voiceService: OfflineVoiceDictationService(),
        );

  factory StgTacticalMobileApp.wired({
    int nodeId = 100,
    BleTransportAdapter? bleAdapter,
  }) {
    final sharedStore = OfflineTacticalStore(nodeId: nodeId);
    final sharedBle = StgBleService(store: sharedStore, adapter: bleAdapter);
    final sharedVoice = OfflineVoiceDictationService();
    return StgTacticalMobileApp._internal(
      store: sharedStore,
      bleService: sharedBle,
      voiceService: sharedVoice,
      sciForms: SciFormsController(
        store: sharedStore,
        bleService: sharedBle,
        voiceService: sharedVoice,
      ),
      startTriage: StartTriageController(
        store: sharedStore,
        bleService: sharedBle,
        voiceService: sharedVoice,
      ),
      offlineMap: const OfflineCartographyController(),
    );
  }

  StgTacticalMobileApp._internal({
    required this.store,
    required this.bleService,
    required this.voiceService,
    required this.sciForms,
    required this.startTriage,
    required this.offlineMap,
  });

  int get backgroundColorHex => StgOledThemeSpec.backgroundHex;
}

void main() {
  final app = StgTacticalMobileApp.wired(nodeId: 100);
  assert(app.backgroundColorHex == 0xFF000000);
}
