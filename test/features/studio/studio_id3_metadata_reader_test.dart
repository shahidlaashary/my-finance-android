import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_finance/modules/studio/application/services/studio_id3_metadata_reader.dart';

void main() {
  test('reads common ID3v2 text frames', () {
    final bytes = _tag([
      _frame('TIT2', [3, ...'Song Name'.codeUnits]),
      _frame('TPE1', [3, ...'Artist'.codeUnits]),
      _frame('TALB', [3, ...'Album'.codeUnits]),
      _frame('TRCK', [3, ...'2/10'.codeUnits]),
      _frame('TDRC', [3, ...'2024'.codeUnits]),
    ]);
    final metadata = const StudioId3MetadataReader().readBytes(bytes);
    expect(metadata.title, 'Song Name');
    expect(metadata.artist, 'Artist');
    expect(metadata.album, 'Album');
    expect(metadata.track, '2/10');
    expect(metadata.year, '2024');
  });

  test('falls back to ID3v1 tags when v2 is absent', () {
    final bytes = Uint8List(128);
    bytes.setRange(0, 3, 'TAG'.codeUnits);
    _put(bytes, 3, 'Legacy Song', 30);
    _put(bytes, 33, 'Legacy Artist', 30);
    _put(bytes, 63, 'Legacy Album', 30);
    _put(bytes, 93, '1999', 4);
    bytes[127] = 17;
    final metadata = const StudioId3MetadataReader().readBytes(bytes);
    expect(metadata.title, 'Legacy Song');
    expect(metadata.artist, 'Legacy Artist');
    expect(metadata.album, 'Legacy Album');
    expect(metadata.year, '1999');
  });
}

Uint8List _tag(List<Uint8List> frames) {
  final body = frames.fold<int>(0, (sum, f) => sum + f.length);
  final out = Uint8List(10 + body);
  out.setRange(0, 3, 'ID3'.codeUnits);
  out[3] = 3; out[4] = 0;
  _synchsafeSet(out, 6, body);
  var offset = 10;
  for (final frame in frames) {
    out.setRange(offset, offset + frame.length, frame);
    offset += frame.length;
  }
  return out;
}

Uint8List _frame(String id, List<int> payload) {
  final out = Uint8List(10 + payload.length);
  out.setRange(0, 4, id.codeUnits);
  ByteData.sublistView(out).setUint32(4, payload.length, Endian.big);
  out.setRange(10, out.length, payload);
  return out;
}

void _synchsafeSet(Uint8List bytes, int offset, int value) {
  bytes[offset] = (value >> 21) & 0x7f;
  bytes[offset + 1] = (value >> 14) & 0x7f;
  bytes[offset + 2] = (value >> 7) & 0x7f;
  bytes[offset + 3] = value & 0x7f;
}

void _put(Uint8List bytes, int offset, String value, int length) {
  final data = value.codeUnits;
  final count = data.length < length ? data.length : length;
  bytes.setRange(offset, offset + count, data.take(count));
}