import 'dart:typed_data';

/// Substrate SCALE compact integer encoding (unsigned).
Uint8List scaleCompactU128(BigInt value) {
  if (value < BigInt.zero) {
    throw ArgumentError('value must be non-negative');
  }
  if (value < BigInt.from(64)) {
    return Uint8List.fromList([(value.toInt() << 2)]);
  }
  if (value < BigInt.from(1) << 14) {
    final v = (value.toInt() << 2) | 0x01;
    return Uint8List.fromList([v & 0xff, (v >> 8) & 0xff]);
  }
  if (value < BigInt.from(1) << 30) {
    final v = (value.toInt() << 2) | 0x02;
    return Uint8List.fromList([
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ]);
  }
  final bytes = _bigIntToLeBytes(value);
  final len = bytes.length;
  final header = ((len - 4) << 2) | 0x03;
  return Uint8List.fromList([header, ...bytes]);
}

Uint8List _bigIntToLeBytes(BigInt value) {
  if (value == BigInt.zero) return Uint8List.fromList([0]);
  var v = value;
  final out = <int>[];
  while (v > BigInt.zero) {
    out.add((v & BigInt.from(0xff)).toInt());
    v >>= 8;
  }
  while (out.length < 4) {
    out.add(0);
  }
  return Uint8List.fromList(out);
}
