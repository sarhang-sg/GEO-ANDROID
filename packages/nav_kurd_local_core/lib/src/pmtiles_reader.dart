import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'core_failure.dart';

/// PMTiles v3 file reader. One serialized file cursor, bounded directories and
/// payloads, no network source, no whole-archive decode and no tile duplication.
final class PmTilesReader {
  PmTilesReader._(this._file, this.fileBytes, this._header, this._fileOffset);
  final RandomAccessFile _file;
  final int _fileOffset;
  final int fileBytes;
  final ByteData _header;
  final _directories = <String, _Directory>{};
  Future<void> _tail = Future.value();
  bool _closing = false;
  Future<void>? _closeFuture;
  Future<Map<String, dynamic>>? _metadata;
  int bytesRead = 127;
  int _directoryBytes = 0;
  static const maximumReadBytes = 8 * 1024 * 1024,
      maximumDecodedBytes = 16 * 1024 * 1024,
      directoryCacheBytes = 4 * 1024 * 1024;
  int _u64(int offset) => _header.getUint64(offset, Endian.little);
  int get minimumZoom => _header.getUint8(100);
  int get maximumZoom => _header.getUint8(101);
  int get internalCompression => _header.getUint8(97);
  int get tileCompression => _header.getUint8(98);
  List<double> get bounds => [
    for (final i in [102, 106, 110, 114])
      _header.getInt32(i, Endian.little) / 1e7,
  ];

  static Future<PmTilesReader> open(
    String path, {
    int offset = 0,
    int? length,
  }) async {
    final file = await File(path).open();
    try {
      final size = await file.length();
      length ??= size - offset;
      if (offset < 0 ||
          length < 127 ||
          offset > size ||
          length > size - offset) {
        throw const CoreFailure(
          'invalid_pmtiles',
          'Invalid archive file range.',
        );
      }
      await file.setPosition(offset);
      final bytes = await file.read(127);
      if (bytes.length != 127 ||
          ascii.decode(bytes.sublist(0, 7), allowInvalid: true) != 'PMTiles' ||
          bytes[7] != 3) {
        throw const CoreFailure(
          'invalid_pmtiles',
          'Expected a PMTiles v3 header.',
        );
      }
      final result = PmTilesReader._(
        file,
        length,
        ByteData.sublistView(bytes),
        offset,
      );
      if (![1, 2].contains(result.internalCompression) ||
          ![1, 2].contains(result.tileCompression) ||
          bytes[99] != 1 ||
          result.minimumZoom > result.maximumZoom ||
          result.maximumZoom > 26) {
        throw const CoreFailure(
          'unsupported_pmtiles',
          'Expected uncompressed/gzip MVT and supported zoom range.',
        );
      }
      for (final offset in [8, 24, 40, 56]) {
        final start = result._u64(offset), size = result._u64(offset + 8);
        if (start < 127 ||
            size < 0 ||
            start > length ||
            size > length - start) {
          throw const CoreFailure(
            'invalid_pmtiles',
            'Archive section exceeds file bounds.',
          );
        }
      }
      return result;
    } catch (_) {
      await file.close();
      rethrow;
    }
  }

  Future<T> _serial<T>(Future<T> Function() task) {
    if (_closing) {
      return Future.error(
        const CoreFailure('closed', 'PMTiles reader is closed.'),
      );
    }
    final result = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        result.complete(await task());
      } catch (e, s) {
        result.completeError(e, s);
      }
    });
    return result.future;
  }

  Future<Uint8List> _read(int offset, int length) async {
    if (offset < 127 ||
        length < 0 ||
        length > maximumReadBytes ||
        offset > fileBytes ||
        length > fileBytes - offset) {
      throw const CoreFailure(
        'invalid_pmtiles',
        'Invalid or oversized random-access request.',
      );
    }
    await _file.setPosition(_fileOffset + offset);
    final result = await _file.read(length);
    bytesRead += result.length;
    if (result.length != length) {
      throw const CoreFailure(
        'corrupt_pmtiles',
        'Archive was truncated while reading.',
      );
    }
    return result;
  }

  Uint8List _decode(Uint8List bytes, int compression) {
    if (compression == 1) return bytes;
    final output = _BoundedBytes(maximumDecodedBytes);
    try {
      final sink = gzip.decoder.startChunkedConversion(output);
      sink.add(bytes);
      sink.close();
    } on FormatException catch (e) {
      throw CoreFailure('corrupt_pmtiles', 'Invalid gzip data: ${e.message}');
    }
    return output.take();
  }

  Future<_Directory> _directory(int offset, int length) async {
    final key = '$offset:$length', cached = _directories.remove(key);
    if (cached != null) {
      _directories[key] = cached;
      return cached;
    }
    final result = _Directory.parse(
      _decode(await _read(offset, length), internalCompression),
    );
    if (result.bytes <= directoryCacheBytes) {
      while (_directoryBytes + result.bytes > directoryCacheBytes) {
        _directoryBytes -= _directories.remove(_directories.keys.first)!.bytes;
      }
      _directories[key] = result;
      _directoryBytes += result.bytes;
    }
    return result;
  }

  Future<Map<String, dynamic>> metadata() => _metadata ??= _serial(() async {
    try {
      return jsonDecode(
            utf8.decode(
              _decode(await _read(_u64(24), _u64(32)), internalCompression),
            ),
          )
          as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw CoreFailure('corrupt_pmtiles', 'Invalid metadata: ${e.message}');
    }
  });
  Future<Uint8List?> tile(int z, int x, int y) => _serial(() async {
    final id = tileId(z, x, y);
    if (z < minimumZoom || z > maximumZoom) return null;
    var offset = _u64(8), length = _u64(16);
    for (var depth = 0; depth < 4; depth++) {
      final directory = await _directory(offset, length),
          index = directory.find(id);
      if (index < 0) return null;
      final run = directory.runs[index],
          relative = directory.offsets[index],
          size = directory.lengths[index];
      if (run > 0) {
        if (id - directory.ids[index] >= run) return null;
        if (relative > _u64(64) || size > _u64(64) - relative) {
          throw const CoreFailure(
            'corrupt_pmtiles',
            'Tile exceeds the tile-data section.',
          );
        }
        return _decode(await _read(_u64(56) + relative, size), tileCompression);
      }
      if (relative > _u64(48) || size > _u64(48) - relative) {
        throw const CoreFailure(
          'corrupt_pmtiles',
          'Directory exceeds the leaf section.',
        );
      }
      offset = _u64(40) + relative;
      length = size;
    }
    throw const CoreFailure(
      'corrupt_pmtiles',
      'PMTiles directory recursion exceeds the format limit.',
    );
  });

  /// The reader returns native tiles only. The renderer must overzoom the
  /// maxzoom-12 source to the approved display zoom 18, not invent new tiles.
  static int tileId(int z, int x, int y) {
    if (z < 0 || z > 26 || x < 0 || y < 0 || x >= (1 << z) || y >= (1 << z)) {
      throw const CoreFailure('invalid_tile', 'Invalid z/x/y coordinate.');
    }
    final n = 1 << z;
    var distance = 0, xx = x, yy = y;
    for (var s = n >> 1; s > 0; s >>= 1) {
      final rx = (xx & s) > 0 ? 1 : 0, ry = (yy & s) > 0 ? 1 : 0;
      distance += s * s * ((3 * rx) ^ ry);
      if (ry == 0) {
        if (rx == 1) {
          xx = s - 1 - xx;
          yy = s - 1 - yy;
        }
        final t = xx;
        xx = yy;
        yy = t;
      }
    }
    return ((1 << (2 * z)) - 1) ~/ 3 + distance;
  }

  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closing = true;
    return _closeFuture = _tail.then((_) async {
      _directories.clear();
      _directoryBytes = 0;
      await _file.close();
    });
  }
}

final class _BoundedBytes implements Sink<List<int>> {
  _BoundedBytes(this.maximum);
  final int maximum;
  final _builder = BytesBuilder(copy: false);
  @override
  void add(List<int> bytes) {
    if (_builder.length + bytes.length > maximum) {
      throw const CoreFailure(
        'pmtiles_size',
        'Decoded tile/directory exceeds 16 MiB.',
      );
    }
    _builder.add(bytes);
  }

  @override
  void close() {}
  Uint8List take() => _builder.takeBytes();
}

final class _Directory {
  _Directory(this.ids, this.runs, this.lengths, this.offsets);
  final Uint64List ids, offsets;
  final Uint32List runs, lengths;
  int get bytes =>
      ids.lengthInBytes +
      runs.lengthInBytes +
      lengths.lengthInBytes +
      offsets.lengthInBytes;
  static _Directory parse(Uint8List data) {
    var cursor = 0;
    int variable() {
      var value = 0;
      for (var shift = 0; shift < 63; shift += 7) {
        if (cursor >= data.length) {
          throw const CoreFailure(
            'corrupt_pmtiles',
            'Truncated directory varint.',
          );
        }
        final byte = data[cursor++];
        value |= (byte & 127) << shift;
        if (byte < 128) return value;
      }
      throw const CoreFailure('corrupt_pmtiles', 'Directory varint overflow.');
    }

    final count = variable();
    if (count > 200000 || count > data.length) {
      throw const CoreFailure(
        'pmtiles_size',
        'Directory entry count exceeds bounds.',
      );
    }
    final ids = Uint64List(count),
        runs = Uint32List(count),
        lengths = Uint32List(count),
        offsets = Uint64List(count);
    var id = 0;
    for (var i = 0; i < count; i++) {
      final delta = variable();
      if (i > 0 && delta == 0) {
        throw const CoreFailure(
          'corrupt_pmtiles',
          'Duplicate directory tile ID.',
        );
      }
      id += delta;
      ids[i] = id;
    }
    for (var i = 0; i < count; i++) {
      final v = variable();
      if (v > 0xffffffff) {
        throw const CoreFailure('corrupt_pmtiles', 'Run length overflow.');
      }
      runs[i] = v;
    }
    for (var i = 0; i < count; i++) {
      final v = variable();
      if (v == 0 || v > maximumDirectoryPayload) {
        throw const CoreFailure('corrupt_pmtiles', 'Invalid entry length.');
      }
      lengths[i] = v;
    }
    for (var i = 0; i < count; i++) {
      final value = variable();
      if (value == 0 && i == 0) {
        throw const CoreFailure(
          'corrupt_pmtiles',
          'First offset cannot be relative.',
        );
      }
      offsets[i] = value == 0 ? offsets[i - 1] + lengths[i - 1] : value - 1;
    }
    if (cursor != data.length) {
      throw const CoreFailure('corrupt_pmtiles', 'Trailing directory bytes.');
    }
    return _Directory(ids, runs, lengths, offsets);
  }

  static const maximumDirectoryPayload = 8 * 1024 * 1024;
  int find(int id) {
    var low = 0, high = ids.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (ids[mid] <= id) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}
