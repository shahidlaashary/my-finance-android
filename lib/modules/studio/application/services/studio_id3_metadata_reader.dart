import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Lightweight, read-only ID3 metadata reader for imported audio assets.
/// Supports ID3v2.2, v2.3, v2.4 text frames and ID3v1/1.1 fallback.
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

  static const _v22Frames = <String, String>{
    'TT2': 'TIT2',
    'TP1': 'TPE1',
    'TAL': 'TALB',
    'TRK': 'TRCK',
    'TYE': 'TYER',
    'TCO': 'TCON',
  };

  // ID3v1 genre codes (the original Winamp/ID3v1 genre table).
  static const _genres = <String>[
    'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk',
    'Grunge', 'Hip-Hop', 'Jazz', 'Metal', 'New Age', 'Oldies',
    'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock', 'Techno',
    'Industrial', 'Alternative', 'Ska', 'Death Metal', 'Pranks',
    'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop', 'Vocal',
    'Jazz+Funk', 'Fusion', 'Trance', 'Classical', 'Instrumental',
    'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise',
    'Alternative Rock', 'Bass', 'Soul', 'Punk', 'Space', 'Meditative',
    'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic',
    'Darkwave', 'Techno-Industrial', 'Electronic', 'Pop-Folk',
    'Eurodance', 'Dream', 'Southern Rock', 'Comedy', 'Cult',
    'Gangsta', 'Top 40', 'Christian Rap', 'Pop/Funk', 'Jungle',
    'Native American', 'Cabaret', 'New Wave', 'Psychedelic',
    'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk',
    'Acid Jazz', 'Polka', 'Retro', 'Musical', 'Rock & Roll',
    'Hard Rock', 'Folk', 'Folk-Rock', 'National Folk', 'Swing',
    'Fast Fusion', 'Bebop', 'Latin', 'Revival', 'Celtic',
    'Bluegrass', 'Avantgarde', 'Gothic Rock', 'Progressive Rock',
    'Psychedelic Rock', 'Symphonic Rock', 'Slow Rock', 'Big Band',
    'Chorus', 'Easy Listening', 'Acoustic', 'Humour', 'Speech',
    'Chanson', 'Opera', 'Chamber Music', 'Sonata', 'Symphony',
    'Booty Bass', 'Primus', 'Porn Groove', 'Satire', 'Slow Jam',
    'Club', 'Tango', 'Samba', 'Folklore', 'Ballad', 'Power Ballad',
    'Rhythmic Soul', 'Freestyle', 'Duet', 'Punk Rock', 'Drum Solo',
    'A Cappella', 'Euro-House', 'Dance Hall', 'Goa', 'Drum & Bass',
    'Club-House', 'Hardcore', 'Terror', 'Indie', 'BritPop',
    'Negerpunk', 'Polsk Punk', 'Beat', 'Christian Gangsta Rap',
    'Heavy Metal', 'Black Metal', 'Crossover', 'Contemporary Christian',
    'Christian Rock', 'Merengue', 'Salsa', 'Thrash Metal',
    'Anime', 'JPop', 'SynthPop',
  ];

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
    if (version < 2 || version > 4 || bytes[4] == 0xff) return {};
    final tagSize = _synchsafe(bytes, 6);
    if (tagSize < 0 || tagSize > bytes.length - 10) return {};
    final end = 10 + tagSize;
    var offset = 10;
    final flags = bytes[5];

    // Extended headers are present in v2.3/v2.4 only.
    if (version >= 3 && (flags & 0x40) != 0) {
      if (offset + 4 > end) return {};
      final extendedSize = version == 4
          ? _synchsafe(bytes, offset)
          : _uint32(bytes, offset);
      final skip = version == 3 ? 4 + extendedSize : extendedSize;
      if (skip <= 0 || offset + skip > end) return {};
      offset += skip;
    }

    final result = <String, String>{};
    while (offset < end) {
      final headerLength = version == 2 ? 6 : 10;
      if (offset + headerLength > end) break;
      final rawId = ascii(bytes, offset, version == 2 ? 3 : 4);
      if (rawId.trim().isEmpty || !RegExp(
        version == 2 ? r'^[A-Z0-9]{3}$' : r'^[A-Z0-9]{4}$',
      ).hasMatch(rawId)) break;

      final id = version == 2 ? (_v22Frames[rawId] ?? rawId) : rawId;
      final frameSize = version == 2
          ? _uint24(bytes, offset + 3)
          : version == 4
              ? _synchsafe(bytes, offset + 4)
              : _uint32(bytes, offset + 4);
      if (frameSize <= 0 || offset + headerLength + frameSize > end) break;

      // Compressed/encrypted frames cannot be safely interpreted as text.
      final frameFlags = version == 2 ? 0 : (bytes[offset + 9]);
      if (id.startsWith('T') && id != 'TXXX' && frameSize > 1 &&
          (frameFlags & 0x0c) == 0) {
        final value = _decodeText(
          bytes.sublist(offset + headerLength, offset + headerLength + frameSize),
        );
        if (value.isNotEmpty) result[id] = value;
      }
      offset += headerLength + frameSize;
    }
    return result;
  }

  Map<String, String> _readV1(Uint8List bytes) {
    if (bytes.length < 128 || ascii(bytes, bytes.length - 128, 3) != 'TAG') return {};
    final start = bytes.length - 128;
    String field(int offset, int length) =>
        _decodeLatin(bytes.sublist(start + offset, start + offset + length));
    final title = field(3, 30);
    final artist = field(33, 30);
    final album = field(63, 30);
    final year = field(93, 4);
    final isV11 = bytes[start + 125] == 0 && bytes[start + 126] != 0;
    final track = isV11 ? bytes[start + 126].toString() : null;
    final genreCode = bytes[start + 127];
    final genre = genreCode < _genres.length ? _genres[genreCode] : null;
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
      ((b[i] & 0x7f) << 21) |
      ((b[i + 1] & 0x7f) << 14) |
      ((b[i + 2] & 0x7f) << 7) |
      (b[i + 3] & 0x7f);

  int _uint24(Uint8List b, int i) =>
      (b[i] << 16) | (b[i + 1] << 8) | b[i + 2];

  int _uint32(Uint8List b, int i) =>
      (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

  String ascii(Uint8List b, int i, int length) =>
      String.fromCharCodes(b.sublist(i, i + length));

  String _decodeText(Uint8List frame) {
    if (frame.isEmpty) return '';
    final encoding = frame[0];
    final payload = frame.sublist(1);
    if (encoding == 3) {
      return utf8.decode(payload, allowMalformed: true)
          .replaceAll('\u0000', '').trim();
    }
    if (encoding == 2) return _decodeUtf16(payload, Endian.big);
    if (encoding == 1) {
      final hasBom = payload.length >= 2 &&
          ((payload[0] == 0xff && payload[1] == 0xfe) ||
           (payload[0] == 0xfe && payload[1] == 0xff));
      final endian = hasBom && payload[0] == 0xff
          ? Endian.little : Endian.big;
      return _decodeUtf16(hasBom ? payload.sublist(2) : payload, endian);
    }
    return _decodeLatin(payload);
  }

  String _decodeUtf16(Uint8List bytes, Endian endian) {
    final usable = bytes.length - (bytes.length % 2);
    if (usable == 0) return '';
    return String.fromCharCodes(List.generate(usable ~/ 2, (i) {
      return ByteData.sublistView(bytes, i * 2, i * 2 + 2)
          .getUint16(0, endian);
    })).replaceAll('\u0000', '').trim();
  }

  String _decodeLatin(Uint8List bytes) =>
      latin1.decode(bytes, allowInvalid: true)
          .replaceAll('\u0000', '').trim();
}
