import 'dart:typed_data';

/// Empaquetador de la trama binaria de 25 bytes (Little-Endian + CRC16-CCITT)
/// idéntica a `firmware/include/frame.h` y `backend/app/frame.py`.
class StgFrame {
  static const int frameSize = 25;
  static const int flagBrigadista = 1 << 0;
  static const int flagPriority = 1 << 1;

  final int flags;
  final int kind;
  final int nodeId;
  final int seq;
  final int nodeTime;
  final double lat;
  final double lon;
  final int severity;
  final int affected;

  const StgFrame({
    this.flags = flagBrigadista | flagPriority,
    required this.kind,
    this.nodeId = 901,
    required this.seq,
    required this.nodeTime,
    required this.lat,
    required this.lon,
    required this.severity,
    required this.affected,
  });

  static int crc16Ccitt(Uint8List data, int length) {
    int crc = 0xFFFF;
    for (int i = 0; i < length; i++) {
      crc ^= (data[i] & 0xFF) << 8;
      for (int bit = 0; bit < 8; bit++) {
        crc = (crc & 0x8000) != 0
            ? ((crc << 1) ^ 0x1021) & 0xFFFF
            : (crc << 1) & 0xFFFF;
      }
    }
    return crc;
  }

  String encodeHex() {
    final bd = ByteData(frameSize);
    bd.setUint8(0, 1); // version = 1
    bd.setUint8(1, flags & 0xFF);
    bd.setUint8(2, kind & 0xFF);
    bd.setUint8(3, 3); // ttl = 3
    bd.setUint16(4, nodeId & 0xFFFF, Endian.little);
    bd.setUint16(6, seq & 0xFFFF, Endian.little);
    bd.setUint32(8, nodeTime & 0xFFFFFFFF, Endian.little);
    bd.setInt32(12, (lat * 1e6).round(), Endian.little);
    bd.setInt32(16, (lon * 1e6).round(), Endian.little);
    bd.setUint8(20, severity.clamp(0, 10));
    bd.setUint16(21, affected.clamp(0, 999), Endian.little);

    final bytes = bd.buffer.asUint8List();
    final crc = crc16Ccitt(bytes, frameSize - 2);
    bd.setUint16(23, crc, Endian.little);

    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
