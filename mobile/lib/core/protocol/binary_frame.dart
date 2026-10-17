import 'dart:typed_data';

class StgFrameException implements Exception {
  final String message;
  StgFrameException(this.message);

  @override
  String toString() => 'StgFrameException: $message';
}

/// Especificación binaria de trama STG-AA (25 bytes, Little-Endian + CRC16-CCITT).
/// Paridad 100% con `firmware/include/frame.h` y `backend/app/frame.py`.
class StgFrame {
  static const int currentVersion = 1;
  static const int flagBrigadista = 0x01;
  static const int flagPriority = 0x02;
  static const int frameSize = 25;
  static const int maxSeverity = 10;
  static const int maxKind = 4;
  static const int coordScale = 1000000;

  static const Map<int, String> kinds = {
    0: 'DERRUMBE',
    1: 'PERSONA_ATRAPADA',
    2: 'INUNDACION',
    3: 'INCENDIO',
    4: 'HERIDO_GRAVE',
  };

  final int version;
  final int flags;
  final int kind;
  final int ttl;
  final int nodeId;
  final int seq;
  final int nodeTime;
  final double lat;
  final double lon;
  final int severity;
  final int affected;

  const StgFrame({
    required this.flags,
    required this.kind,
    required this.nodeId,
    required this.seq,
    required this.nodeTime,
    required this.lat,
    required this.lon,
    this.severity = 0,
    this.affected = 0,
    this.ttl = 3,
    this.version = currentVersion,
  });

  bool get verified => (flags & flagBrigadista) != 0;
  bool get isPriority => (flags & flagPriority) != 0;

  static int crc16Ccitt(Uint8List data, [int? length]) {
    final len = length ?? data.length;
    int crc = 0xFFFF;
    for (int i = 0; i < len; i++) {
      crc ^= (data[i] & 0xFF) << 8;
      for (int bit = 0; bit < 8; bit++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  Uint8List encode() {
    final bytes = Uint8List(frameSize);
    final view = ByteData.sublistView(bytes);
    view.setUint8(0, version);
    view.setUint8(1, flags);
    view.setUint8(2, kind);
    view.setUint8(3, ttl);
    view.setUint16(4, nodeId, Endian.little);
    view.setUint16(6, seq, Endian.little);
    view.setUint32(8, nodeTime, Endian.little);
    view.setInt32(12, (lat * coordScale).round(), Endian.little);
    view.setInt32(16, (lon * coordScale).round(), Endian.little);
    view.setUint8(20, severity);
    view.setUint16(21, affected, Endian.little);

    final crc = crc16Ccitt(bytes, 23);
    view.setUint16(23, crc, Endian.little);
    return bytes;
  }

  String toHex() {
    final raw = encode();
    final sb = StringBuffer();
    for (final b in raw) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static StgFrame decode(Uint8List raw) {
    if (raw.length != frameSize) {
      throw StgFrameException(
          'Longitud invalida: ${raw.length} bytes, se esperaban $frameSize');
    }
    final view = ByteData.sublistView(raw);
    final expectedCrc = view.getUint16(23, Endian.little);
    final actualCrc = crc16Ccitt(raw, 23);
    if (expectedCrc != actualCrc) {
      throw StgFrameException('CRC invalido');
    }

    final version = view.getUint8(0);
    final flags = view.getUint8(1);
    final kind = view.getUint8(2);
    final ttl = view.getUint8(3);
    final nodeId = view.getUint16(4, Endian.little);
    final seq = view.getUint16(6, Endian.little);
    final nodeTime = view.getUint32(8, Endian.little);
    final latE6 = view.getInt32(12, Endian.little);
    final lonE6 = view.getInt32(16, Endian.little);
    final severity = view.getUint8(20);
    final affected = view.getUint16(21, Endian.little);

    if (version != currentVersion) {
      throw StgFrameException('Version no soportada: $version');
    }
    if (!kinds.containsKey(kind)) {
      throw StgFrameException('Tipo de emergencia desconocido: $kind');
    }
    if (severity > maxSeverity) {
      throw StgFrameException('Severidad fuera de rango: $severity');
    }

    final lat = latE6 / coordScale;
    final lon = lonE6 / coordScale;
    if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) {
      throw StgFrameException('Coordenadas fuera de rango');
    }

    return StgFrame(
      version: version,
      flags: flags,
      kind: kind,
      ttl: ttl,
      nodeId: nodeId,
      seq: seq,
      nodeTime: nodeTime,
      lat: lat,
      lon: lon,
      severity: severity,
      affected: affected,
    );
  }

  static StgFrame fromHex(String hex) {
    final clean = hex.trim();
    if (clean.length != frameSize * 2) {
      throw StgFrameException('Longitud hexadecimal invalida');
    }
    final bytes = Uint8List(frameSize);
    for (int i = 0; i < frameSize; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return decode(bytes);
  }
}
