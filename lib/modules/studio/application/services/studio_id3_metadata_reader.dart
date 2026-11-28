import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lightweight ID3 metadata reader for imported audio assets.
/// Supports common ID3v2 text frames and ID3v1 fallback; it does not modify media.
class StudioAudioMetadata {
  const StudioAudioMetadata({
    this.title,
    this.artist,
    this.album,
    this.track,
    this.year,
    this.genre,
  });

  final String? title;
  final String? artist;
  final String? album;
  final String? track;
  final String? year;
  final String? genre;

  bool get isEmpty => [title, artist, album, track, year, genre]
      .every((value) => value == null || value.trim().isEmpty);
}

class StudioId3MetadataReader {
  const StudioId3MetadataReader();

  Future<StudioAudioMetadata> readFile(String path) async =>
      readBytes(await File(path).readAsBytes());

  StudioAudioMetadata readBytes(Uint8List bytes) {
    final v2 = _readV2(bytes);
    final v1 = _readV1(bytes);
    return StudioAudioMetadata(
      title: _prefer(v2['TIT2'], v1['title']),
      artist: _prefer(v2['TPE1'], v1['artist']),
      album: _prefer(v2['TALB'], v1['album']),
      track: _prefer(v2['TRCK'], v1['track']),
      year: _prefer(v2['TDRC'] ?? v2['TYER'], v1['year']),
      genre: _prefer(v2['TCON'], v1['genre']),
    );
  }

  String? _prefer(String? first, String? fallback) =>
      first?.trim().isNotEmpty == true ? first!.trim() : fallback?.trim();

  Map<String, String> _readV2(Uint8List bytes) {
    if (bytes.length < 10 || ascii(bytes, 0, 3) != 'ID3') return {};
    final version = bytes[3];
    if (version < 2 || version > 4) return {};
    final tagSize = _synchsafe(bytes, 6);
    final end = (10 + tagSize).clamp(10, bytes.length);
    var offset = 10;
    final result = <String, String>{};
    while (offset + 10 <= end) {
      final id = ascii(bytes, offset, 4);
      if (id.trim().isEmpty || !RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
      final frameSize = version == 4 ? _synchsafe(bytes, offset + 4) : _uint32(bytes, offset + 4);
      if (frameSize <= 0 || offset + 10 + frameSize > end) break;
      if (id.startsWith('T') && id != 'TXXX' && frameSize > 1) {
        final value = _decodeText(bytes.sublist(offset + 10, offset + 10 + frameSize));
        if (value.isNotEmpty) result[id] = value;
      }
      offset += 10 + frameSize;
    }
    return result;
  }

  Map<String, String> _readV1(Uint8List bytes) {
    if (bytes.length < 128 || ascii(bytes, bytes.length - 128, 3) != 'TAG') return {};
    final start = bytes.length - 128;
    String field(int offset, int length) => _decodeLatin(bytes.sublist(start + offset, start + offset + length));
    final title = field(3, 30), artist = field(33, 30), album = field(63, 30), year = field(93, 4);
    final track = bytes[start + 125] == 0 && bytes[start + 126] != 0 ? bytes[start + 126].toString() : null;
    final genreCode = bytes[start + 127];
    final genre = genreCode == 255 ? null : genreCode.toString();
    return {
      if (title.isNotEmpty) 'title': title,
      if (artist.isNotEmpty) 'artist': artist,
      if (album.isNotEmpty) 'album': album,
      if (year.isNotEmpty) 'year': year,
      if (track != null) 'track': track,
      if (genre != null) 'genre': genre,
    };
  }

  int _synchsafe(Uint8List b, int i) =>
      ((b[i] & 0x7f) << 21) | ((b[i + 1] & 0x7f) << 14) |
      ((b[i + 2] & 0x7f) << 7) | (b[i + 3] & 0x7f);

  int _uint32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  String ascii(Uint8List b, int i, int length) =>
      String.fromCharCodes(b.sublist(i, i + length));

  String _decodeText(Uint8List frame) {
    if (frame.isEmpty) return '';
    final encoding = frame[0];
    final payload = frame.sublist(1);
    if (encoding == 3) return utf8.decode(payload, allowMalformed: true).replaceAll('\u0000', '').trim();
    if (encoding == 2) return _decodeUtf16(payload, Endian.big);
    if (encoding == 1) {
      final endian = payload.length >= 2 && payload[0] == 0xff && payload[1] == 0xfe ? Endian.little : Endian.big;
      final data = payload.length >= 2 && (payload[0] == 0xff || payload[0] == 0xfe) ? payload.sublist(2) : payload;
      return _decodeUtf16(data, endian);
    }
    return _decodeLatin(payload);
  }

  String _decodeUtf16(Uint8List bytes, Endian endian) {
    final usable = bytes.length - (bytes.length % 2);
    if (usable == 0) return '';
    return String.fromCharCodes(List.generate(usable ~/ 2, (i) {
      return ByteData.sublistView(bytes, i * 2, i * 2 + 2).getUint16(0, endian);
    })).replaceAll('\u0000', '').trim();
  }

  String _decodeLatin(Uint8List bytes) =>
      latin1.decode(bytes, allowInvalid: true).replaceAll('\u0000', '').trim();
}
