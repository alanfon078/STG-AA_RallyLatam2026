import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/database/local_store.dart';
import '../core/protocol/binary_frame.dart';

enum BleConnectionStatus {
  DISCONNECTED,
  SCANNING,
  CONNECTING,
  CONNECTED,
  RECONNECTING,
}

/// Abstracción del adaptador físico BLE (implementable con `flutter_blue_plus` en dispositivo real
/// o con transporte simulado en pruebas sin hardware).
abstract class BleTransportAdapter {
  Future<List<String>> scanForStgNodes({Duration timeout});
  Future<void> connect(String deviceId);
  Future<void> disconnect();
  Future<void> writeRxCharacteristic(Uint8List payload);
  Stream<Uint8List> get txNotifications;
  Stream<bool> get connectionStateStream;
}

/// Servicio BLE táctico (`lib/services/ble_service.dart`):
/// - Escaneo de nodos `STG-AA-NODO-*`
/// - Emparejamiento y reconexión automática permanente
/// - Cola de transmisión con reintentos hacia el nodo portátil
/// - Recepción de `ACK:<node_id>:<seq>` y tramas descendentes (*downlink*) desde el Puesto de Comando
class StgBleService {
  static const String deviceNamePrefix = 'STG-AA-NODO-';
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  static const String rxCharacteristicUuid =
      '6e400002-b5a3-f393-e0a9-e50e24dcca9e';
  static const String txCharacteristicUuid =
      '6e400003-b5a3-f393-e0a9-e50e24dcca9e';

  final OfflineTacticalStore store;
  final BleTransportAdapter? adapter;
  final Duration reconnectInterval;

  BleConnectionStatus _status = BleConnectionStatus.DISCONNECTED;
  String? _pairedDeviceId;
  bool _autoReconnectEnabled = true;
  Timer? _reconnectTimer;
  StreamSubscription<Uint8List>? _txSub;
  StreamSubscription<bool>? _connSub;

  final StreamController<BleConnectionStatus> _statusController =
      StreamController<BleConnectionStatus>.broadcast();

  StgBleService({
    required this.store,
    this.adapter,
    this.reconnectInterval = const Duration(seconds: 3),
  });

  BleConnectionStatus get status => _status;
  String? get pairedDeviceId => _pairedDeviceId;
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;

  void _setStatus(BleConnectionStatus next) {
    _status = next;
    if (!_statusController.isClosed) {
      _statusController.add(next);
    }
  }

  Future<List<String>> scanAndPair({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    _setStatus(BleConnectionStatus.SCANNING);
    final currentAdapter = adapter;
    if (currentAdapter == null) {
      _setStatus(BleConnectionStatus.DISCONNECTED);
      return const [];
    }
    final devices = await currentAdapter.scanForStgNodes(timeout: timeout);
    final matching =
        devices.where((d) => d.startsWith(deviceNamePrefix)).toList();
    if (matching.isNotEmpty) {
      await pairWithDevice(matching.first);
    } else {
      _setStatus(BleConnectionStatus.DISCONNECTED);
    }
    return matching;
  }

  Future<void> pairWithDevice(String deviceId) async {
    _pairedDeviceId = deviceId;
    _setStatus(BleConnectionStatus.CONNECTING);
    final currentAdapter = adapter;
    if (currentAdapter == null) {
      _setStatus(BleConnectionStatus.CONNECTED);
      await flushOutboxQueue();
      return;
    }

    await _txSub?.cancel();
    await _connSub?.cancel();

    _connSub = currentAdapter.connectionStateStream.listen((connected) {
      if (connected) {
        _setStatus(BleConnectionStatus.CONNECTED);
        flushOutboxQueue();
      } else {
        _setStatus(BleConnectionStatus.DISCONNECTED);
        if (_autoReconnectEnabled && _pairedDeviceId != null) {
          _scheduleAutoReconnect();
        }
      }
    });

    _txSub = currentAdapter.txNotifications.listen(onRawNotificationReceived);

    await currentAdapter.connect(deviceId);
    _setStatus(BleConnectionStatus.CONNECTED);
    await flushOutboxQueue();
  }

  void _scheduleAutoReconnect() {
    _reconnectTimer?.cancel();
    _setStatus(BleConnectionStatus.RECONNECTING);
    _reconnectTimer = Timer(reconnectInterval, () async {
      final target = _pairedDeviceId;
      if (target != null &&
          _autoReconnectEnabled &&
          _status != BleConnectionStatus.CONNECTED) {
        try {
          await pairWithDevice(target);
        } catch (_) {
          _scheduleAutoReconnect();
        }
      }
    });
  }

  /// Drena la cola local enviando todas las tramas pendientes hacia el nodo portátil por BLE
  Future<int> flushOutboxQueue() async {
    if (_status != BleConnectionStatus.CONNECTED) return 0;
    final pending = store.pendingForTransmission();
    int transmitted = 0;

    for (final item in pending) {
      final payload = item.frame.encode();
      if (adapter != null) {
        await adapter!.writeRxCharacteristic(payload);
      }
      store.markSent(item.compactId);
      transmitted += 1;
    }
    return transmitted;
  }

  /// Procesa notificaciones entrantes desde la característica TX del nodo ESP32:
  /// - Si es texto `ACK:<node_id>:<seq>`, marca el reporte en la cola local como `ACKED`.
  /// - Si es una trama binaria de 25 bytes, la decodifica como orden/alerta descendente (*downlink*).
  void onRawNotificationReceived(Uint8List data) {
    if (data.length == StgFrame.frameSize) {
      try {
        final downlink = StgFrame.decode(data);
        store.handleDownlinkFrame(downlink);
        return;
      } catch (_) {
        // Si no es trama binaria válida, probamos decodificar como mensaje ASCII ACK
      }
    }

    final text = utf8.decode(data, allowMalformed: true).trim();
    if (text.startsWith('ACK:')) {
      store.handleAckNotification(text);
    }
  }

  void setAutoReconnect(bool enabled) {
    _autoReconnectEnabled = enabled;
    if (!enabled) {
      _reconnectTimer?.cancel();
    }
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _txSub?.cancel();
    await _connSub?.cancel();
    await _statusController.close();
  }
}
