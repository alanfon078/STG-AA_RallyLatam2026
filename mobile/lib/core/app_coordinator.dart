import '../features/formularios_sci/sci_forms_controller.dart';
import '../features/mapa_offline/offline_map_service.dart';
import '../features/triaje/start_triage_controller.dart';
import '../services/ble_service.dart';
import 'database/local_store.dart';
import 'theme/oled_theme.dart';
import 'voice/offline_voice_service.dart';

/// Coordinador raíz de los servicios y controladores de la Terminal Táctica STG-AA.
class StgTacticalMobileApp {
  final OfflineTacticalStore store;
  final StgBleService bleService;
  final OfflineVoiceDictationService voiceService;
  final SciFormsController sciForms;
  final StartTriageController startTriage;
  final OfflineCartographyController offlineMap;

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
