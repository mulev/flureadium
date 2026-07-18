import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Builds a canonical 44-byte PCM WAV header declaring [dataSize] bytes of
/// audio data. The header is valid on its own, so a player can start decoding
/// before the data chunk fully arrives.
Uint8List wavHeader({
  required int dataSize,
  int sampleRate = 8000,
  int channels = 1,
  int bitsPerSample = 16,
}) {
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final blockAlign = channels * (bitsPerSample ~/ 8);
  final header = ByteData(44);
  void putAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      header.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  putAscii(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  putAscii(8, 'WAVE');
  putAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
  header.setUint16(20, 1, Endian.little); // audioFormat = PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  putAscii(36, 'data');
  header.setUint32(40, dataSize, Endian.little);
  return header.buffer.asUint8List();
}

/// Serves a fixed byte payload over a loopback HTTP server with byte-range
/// support, trickling the tail of each range response so a read-ahead request
/// stays in flight during playback. Reports (via [onClientCancel]) when the
/// client drops an in-flight range request — the benign AVFoundation
/// range-request cancellation the iOS load-failure reporter must not surface
/// as an error. Serving a single complete, seekable resource keeps the only
/// possible failure a cancellation, so a test can assert both that the
/// cancellation happened and that no error surfaced.
class StreamedAudioServer {
  StreamedAudioServer._(
    this._server,
    this._content,
    this._contentType,
    this._prefixBytes,
    this._holdTimeout,
  ) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final Uint8List _content;
  final String _contentType;
  final int _prefixBytes;
  final Duration _holdTimeout;

  /// Invoked once each time the client cancels an in-flight range response —
  /// it closes the connection before the declared body has been fully sent.
  void Function()? onClientCancel;

  /// URL of the served resource, for an audiobook manifest's reading order.
  String get url => 'http://127.0.0.1:${_server.port}/audio.wav';

  /// Starts a server serving [content] as [contentType]. Each data range sends
  /// its first [prefixBytes] immediately (so playback can start) and then holds
  /// the response open, deliberately incomplete, for up to [holdTimeout]. A
  /// client that closes the connection during that hold has cancelled the
  /// in-flight request — the benign AVFoundation range-request cancellation the
  /// iOS reporter must not surface as an error.
  static Future<StreamedAudioServer> start({
    required Uint8List content,
    String contentType = 'application/octet-stream',
    int prefixBytes = 262144,
    Duration holdTimeout = const Duration(seconds: 30),
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return StreamedAudioServer._(
      server,
      content,
      contentType,
      prefixBytes,
      holdTimeout,
    );
  }

  /// Convenience: serve [seconds] of valid, seekable silent 8 kHz mono WAV.
  static Future<StreamedAudioServer> startSilentWav({
    int seconds = 60,
    int prefixBytes = 262144,
    Duration holdTimeout = const Duration(seconds: 30),
  }) {
    const sampleRate = 8000;
    const bytesPerSample = 2; // 16-bit mono
    final dataSize = sampleRate * bytesPerSample * seconds;
    final header = wavHeader(dataSize: dataSize, sampleRate: sampleRate);
    final wav = Uint8List(header.length + dataSize)
      ..setRange(0, header.length, header);
    return start(
      content: wav,
      contentType: 'audio/wav',
      prefixBytes: prefixBytes,
      holdTimeout: holdTimeout,
    );
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final total = _content.length;
    var start = 0;
    var end = total - 1;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final isRange = rangeHeader != null && rangeHeader.startsWith('bytes=');
    if (isRange) {
      final spec = rangeHeader.substring('bytes='.length).split('-');
      start = int.tryParse(spec[0]) ?? 0;
      if (spec.length > 1 && spec[1].isNotEmpty) {
        end = int.tryParse(spec[1]) ?? end;
      }
      start = start.clamp(0, total - 1);
      end = end.clamp(start, total - 1);
    }

    final socket = await request.response.detachSocket(writeHeaders: false);

    // A HEAD (or length probe) only needs the size — answer instantly and in
    // full so the player learns the duration and can seek.
    if (request.method == 'HEAD') {
      await _writeAndClose(
        socket,
        'HTTP/1.1 200 OK\r\n'
        'Content-Type: $_contentType\r\n'
        'Accept-Ranges: bytes\r\n'
        'Content-Length: $total\r\n'
        'Connection: close\r\n\r\n',
      );
      return;
    }

    final length = end - start + 1;
    final statusLine = isRange
        ? 'HTTP/1.1 206 Partial Content'
        : 'HTTP/1.1 200 OK';
    final headers = StringBuffer()
      ..write('$statusLine\r\n')
      ..write('Content-Type: $_contentType\r\n')
      ..write('Accept-Ranges: bytes\r\n')
      ..write('Content-Length: $length\r\n');
    if (isRange) {
      headers.write('Content-Range: bytes $start-$end/$total\r\n');
    }
    headers.write('Connection: close\r\n\r\n');

    // A client that closes the connection while the response is still
    // incomplete has cancelled the in-flight request.
    final closedByClient = Completer<void>();
    final sub = socket.listen(
      (_) {},
      onDone: () {
        if (!closedByClient.isCompleted) closedByClient.complete();
      },
      onError: (_) {
        if (!closedByClient.isCompleted) closedByClient.complete();
      },
      cancelOnError: true,
    );

    var cancelled = false;
    try {
      socket.add(utf8.encode(headers.toString()));
      // Send a startup prefix so playback can begin, then hold the rest back so
      // the request stays in flight (incomplete) and a seek can supersede it.
      final prefixEnd = (start + _prefixBytes - 1) <= end
          ? start + _prefixBytes - 1
          : end;
      socket.add(_content.sublist(start, prefixEnd + 1));
      await socket.flush();

      if (prefixEnd < end) {
        await closedByClient.future.timeout(_holdTimeout, onTimeout: () {});
        if (closedByClient.isCompleted) {
          cancelled = true;
        } else {
          // No cancellation within the window: finish the body cleanly.
          socket.add(_content.sublist(prefixEnd + 1, end + 1));
          await socket.flush();
        }
      }
    } catch (_) {
      cancelled = true;
    } finally {
      await sub.cancel();
      try {
        await socket.close();
      } catch (_) {}
      socket.destroy();
    }
    if (cancelled) onClientCancel?.call();
  }

  Future<void> _writeAndClose(Socket socket, String data) async {
    try {
      socket.add(utf8.encode(data));
      await socket.flush();
    } catch (_) {
      // ignore write failures on a probe response
    } finally {
      try {
        await socket.close();
      } catch (_) {}
      socket.destroy();
    }
  }
}
