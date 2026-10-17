import 'dart:async';
import '../../features/formularios_sci/sci_models.dart';
import '../../features/triaje/start_triage_model.dart';
import '../protocol/binary_frame.dart';

enum OutboxSyncState {
  PENDING, // En cola local esperando conexión BLE al nodo
  SENT, // Transmitido por BLE al nodo, esperando ACK de radio LoRa
  ACKED, // Confirmado (ACK:<node_id>:<seq> recibido desde el nodo LoRa)
  FAILED, // Excedió reintentos, pendiente de reintento manual/automático
}

class OutboxEntry {
  final String compactId;
  final int nodeId;
  final int seq;
  final StgFrame frame;
  final String formType; // SCI-201, SCI-211, SCI-207, ROADBLOCK
  OutboxSyncState state;
  int attempts;
  final int createdAtSec;
  int? ackedAtSec;

  OutboxEntry({
    required this.compactId,
    required this.nodeId,
    required this.seq,
    required this.frame,
    required this.formType,
    this.state = OutboxSyncState.PENDING,
    this.attempts = 0,
    required this.createdAtSec,
    this.ackedAtSec,
  });
}

/// Esquema SQLite (sqflite / drift) para persistencia local reactiva Offline-First
const List<String> sqliteOfflineSchema = [
  '''
  CREATE TABLE IF NOT EXISTS sci_201_reports (
    compact_id TEXT PRIMARY KEY,
    incident_name TEXT NOT NULL,
    commander_name TEXT NOT NULL,
    kind INTEGER NOT NULL,
    severity INTEGER NOT NULL,
    perimeter_json TEXT NOT NULL,
    facilities_json TEXT NOT NULL,
    situation_summary TEXT NOT NULL,
    safety_message TEXT NOT NULL,
    created_at_sec INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS sci_211_resources (
    compact_id TEXT PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    resource_class TEXT NOT NULL,
    resource_type INTEGER NOT NULL,
    category TEXT NOT NULL,
    status TEXT NOT NULL,
    supervisor TEXT NOT NULL,
    subordinates_count INTEGER NOT NULL,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    updated_at_sec INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS sci_207_triage (
    compact_id TEXT PRIMARY KEY,
    acv_name TEXT NOT NULL,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    rojo_count INTEGER NOT NULL,
    amarillo_count INTEGER NOT NULL,
    verde_count INTEGER NOT NULL,
    negro_count INTEGER NOT NULL,
    severity INTEGER NOT NULL,
    updated_at_sec INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS road_blocks (
    compact_id TEXT PRIMARY KEY,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    severity INTEGER NOT NULL,
    radius_m REAL NOT NULL,
    description TEXT NOT NULL,
    created_at_sec INTEGER NOT NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS outbox_queue (
    compact_id TEXT PRIMARY KEY,
    node_id INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    frame_hex TEXT NOT NULL,
    form_type TEXT NOT NULL,
    state TEXT NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0,
    created_at_sec INTEGER NOT NULL,
    acked_at_sec INTEGER NULL
  )
  ''',
  '''
  CREATE TABLE IF NOT EXISTS downlink_orders (
    compact_id TEXT PRIMARY KEY,
    node_id INTEGER NOT NULL,
    seq INTEGER NOT NULL,
    kind INTEGER NOT NULL,
    severity INTEGER NOT NULL,
    lat REAL NOT NULL,
    lon REAL NOT NULL,
    received_at_sec INTEGER NOT NULL
  )
  ''',
];

/// Repositorio reactivo Offline-First con identificadores únicos compactos
class OfflineTacticalStore {
  final int nodeId;
  int _seqCounter = 0;
  int _compactSeq = 0;

  final List<Sci201Report> _sci201 = [];
  final Map<String, Sci211Resource> _sci211ByCode = {};
  final List<StartTriageSummary> _sci207 = [];
  final List<RoadBlockReport> _roadBlocks = [];
  final List<CommandTransferPayload> _transfers = [];
  final List<OutboxEntry> _outbox = [];
  final List<StgFrame> _downlinkFrames = [];

  final StreamController<List<OutboxEntry>> _outboxController =
      StreamController<List<OutboxEntry>>.broadcast();
  final StreamController<StgFrame> _downlinkController =
      StreamController<StgFrame>.broadcast();

  OfflineTacticalStore({this.nodeId = 100});

  Stream<List<OutboxEntry>> get outboxStream => _outboxController.stream;
  Stream<StgFrame> get downlinkStream => _downlinkController.stream;

  /// Genera un identificador único compacto en Base36 (< 12 caracteres)
  /// combinando nodeId, epoch corto y contador monotónico.
  String nextCompactId([String prefix = 'S']) {
    _compactSeq = (_compactSeq + 1) & 0xFFFF;
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0xFFFFFFF;
    final n = nodeId.toRadixString(36).toUpperCase();
    final t = ts.toRadixString(36).toUpperCase();
    final c = _compactSeq.toRadixString(36).toUpperCase();
    return '$prefix$n-$t$c';
  }

  int nextSeq() {
    _seqCounter = (_seqCounter % 65535) + 1;
    return _seqCounter;
  }

  List<Sci201Report> get sci201Reports => List.unmodifiable(_sci201);
  List<Sci211Resource> get sci211Resources =>
      List.unmodifiable(_sci211ByCode.values);
  List<StartTriageSummary> get sci207Summaries => List.unmodifiable(_sci207);
  List<RoadBlockReport> get roadBlocks => List.unmodifiable(_roadBlocks);
  List<CommandTransferPayload> get commandTransfers =>
      List.unmodifiable(_transfers);
  List<OutboxEntry> get outboxEntries => List.unmodifiable(_outbox);
  List<StgFrame> get downlinkFrames => List.unmodifiable(_downlinkFrames);

  int get pendingCount => _outbox
      .where((e) =>
          e.state == OutboxSyncState.PENDING || e.state == OutboxSyncState.SENT)
      .length;

  int get ackedCount =>
      _outbox.where((e) => e.state == OutboxSyncState.ACKED).length;

  OutboxEntry saveSci201(Sci201Report report) {
    _sci201.add(report);
    final seq = nextSeq();
    final frame = report.toBinaryFrame(nodeId: nodeId, seq: seq);
    return _enqueueFrame(frame, 'SCI-201', report.createdAtSec);
  }

  Sci211Resource upsertSci211Resource(Sci211Resource resource) {
    _sci211ByCode[resource.code] = resource;
    return resource;
  }

  OutboxEntry saveSci207Triage(StartTriageSummary summary) {
    _sci207.add(summary);
    final seq = nextSeq();
    final frame = summary.toBinaryFrame(nodeId: nodeId, seq: seq);
    return _enqueueFrame(frame, 'SCI-207', summary.updatedAtSec);
  }

  OutboxEntry saveRoadBlock(RoadBlockReport report) {
    _roadBlocks.add(report);
    final seq = nextSeq();
    final frame = report.toBinaryFrame(nodeId: nodeId, seq: seq);
    return _enqueueFrame(frame, 'ROADBLOCK', report.createdAtSec);
  }

  void recordCommandTransfer(CommandTransferPayload transfer) {
    _transfers.add(transfer);
  }

  OutboxEntry _enqueueFrame(StgFrame frame, String formType, int nowSec) {
    final entry = OutboxEntry(
      compactId: nextCompactId('Q'),
      nodeId: frame.nodeId,
      seq: frame.seq,
      frame: frame,
      formType: formType,
      state: OutboxSyncState.PENDING,
      attempts: 0,
      createdAtSec: nowSec,
    );
    _outbox.add(entry);
    _notifyOutbox();
    return entry;
  }

  List<OutboxEntry> pendingForTransmission({int maxAttempts = 5}) {
    return _outbox
        .where((e) =>
            (e.state == OutboxSyncState.PENDING ||
                e.state == OutboxSyncState.SENT) &&
            e.attempts < maxAttempts)
        .toList();
  }

  void markSent(String compactId) {
    for (final entry in _outbox) {
      if (entry.compactId == compactId) {
        entry.attempts += 1;
        entry.state = OutboxSyncState.SENT;
        _notifyOutbox();
        return;
      }
    }
  }

  bool handleAckNotification(String message, {int? ackTimeSec}) {
    // Formato esperado desde firmware BLE TX: "ACK:<node_id>:<seq>"
    final trimmed = message.trim();
    if (!trimmed.startsWith('ACK:')) return false;
    final parts = trimmed.split(':');
    if (parts.length != 3) return false;
    final ackNodeId = int.tryParse(parts[1]);
    final ackSeq = int.tryParse(parts[2]);
    if (ackNodeId == null || ackSeq == null) return false;

    final now =
        ackTimeSec ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    for (final entry in _outbox) {
      if (entry.nodeId == ackNodeId && entry.seq == ackSeq) {
        entry.state = OutboxSyncState.ACKED;
        entry.ackedAtSec = now;
        _notifyOutbox();
        return true;
      }
    }
    return false;
  }

  void handleDownlinkFrame(StgFrame frame) {
    _downlinkFrames.add(frame);
    if (!_downlinkController.isClosed) {
      _downlinkController.add(frame);
    }
  }

  void _notifyOutbox() {
    if (!_outboxController.isClosed) {
      _outboxController.add(List.unmodifiable(_outbox));
    }
  }

  void dispose() {
    _outboxController.close();
    _downlinkController.close();
  }
}
