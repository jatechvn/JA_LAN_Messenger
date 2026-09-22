import 'dart:async';
import 'package:logging/logging.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../constants.dart';
import '../models/file_transfer_task.dart';
import 'beebeep_session.dart';
import 'protocol_beebeep.dart';

typedef OnTransferUpdated = void Function(FileTransferTask task);

class FileTransferEngine {
  ServerSocket? _server;
  final Duration inactivityTimeout;
  FileTransferEngine({this.inactivityTimeout = const Duration(seconds: 45)});
  final _tasks = <String, FileTransferTask>{};
  final _offers = <String, Map<String, dynamic>>{};
  final _sessions = <BeebeepSession>{};
  final _taskSessions = <String, BeebeepSession>{};
  final _timers = <String, Timer>{};
  OnTransferUpdated? onTransferUpdated;
  List<int> Function(String)? helloBuilder;
  String Function()? passwordProvider;
  bool Function(String, List<int>)? sendOffer;
  bool Function(String)? isPeerConnected;
  String? downloadDirectory;
  int get port => _server?.port ?? defaultFileTransferPort;
  bool get isListening => _server != null;
  List<FileTransferTask> get tasks => _tasks.values.toList();

  Future<String> getDefaultDownloadDir() async {
    final root =
        downloadDirectory ??
        p.join(
          Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME']!,
          'Downloads',
          'JA_LAN_Messenger',
        );
    await Directory(root).create(recursive: true);
    return root;
  }

  Future<bool> startServer({int port = defaultFileTransferPort}) async {
    if (_server != null) return true;
    for (final candidate in [port, port + 2, port + 4, 0]) {
      try {
        _server = await ServerSocket.bind(InternetAddress.anyIPv4, candidate);
        _server!.listen(_upload);
        return true;
      } on SocketException {
        continue;
      }
    }
    return false;
  }

  static Map<String, dynamic> parseOffer(Map<String, dynamic> message) {
    final fields = (message['data'] as String).split(
      ProtocolBeebeep.dataFieldSeparator,
    );
    if (message['header'] != ProtocolBeebeep.headerFile || fields.length < 4) {
      throw const FormatException('Invalid file offer');
    }
    final port = int.tryParse(fields[0]),
        size = int.tryParse(fields[1]),
        id = int.tryParse(fields[2]);
    if (port == null ||
        port < 1 ||
        port > 65535 ||
        size == null ||
        size < 0 ||
        id == null ||
        id <= 0 ||
        fields[3].isEmpty) {
      throw const FormatException('Invalid file metadata');
    }
    return {
      'port': port,
      'size': size,
      'id': fields[2],
      'token': fields[3],
      'name': message['text'],
      'fields': fields,
      'groupId': groupIdFromFields(fields),
    };
  }

  /// Trường thứ 14, sau 13 trường BeeBEEP. Client cũ bỏ qua phần thêm này.
  static final RegExp groupIdPattern = RegExp(
    r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}$',
  );

  static String? groupIdFromFields(List<String> fields) {
    if (fields.length <= 13) return null;
    final raw = fields[13].trim();
    if (!groupIdPattern.hasMatch(raw)) return null;
    return raw;
  }

  static List<int> _packet(Map<String, dynamic> offer) =>
      ProtocolBeebeep.packet(
        ProtocolBeebeep.headerFile,
        '${DateTime.now().microsecondsSinceEpoch}',
        text: offer['name'] as String,
        data: (offer['fields'] as List<String>).join(
          ProtocolBeebeep.dataFieldSeparator,
        ),
        flags: 1,
      );
  static List<int> _ack(int count, int total) {
    final bytes = utf8.encode(
      [count, total, 1, ' '].join(ProtocolBeebeep.dataFieldSeparator),
    );
    return [...bytes, ...List.filled((16 - bytes.length % 16) % 16, 48)];
  }

  void _update(FileTransferTask task) {
    if (_terminal(task)) {
      _timers.remove(task.id)?.cancel();
      Logger('Diagnostics').info(
        'transfer_${task.status.name} upload=${task.isUpload} bytes=${task.transferredBytes}/${task.fileSize}',
      );
    } else if (task.status == TransferStatus.transferring) {
      _watch(task);
    }
    onTransferUpdated?.call(task);
  }

  void _watch(FileTransferTask task) {
    _timers.remove(task.id)?.cancel();
    _timers[task.id] = Timer(inactivityTimeout, () {
      _fail(task, 'Transfer inactivity timeout');
      _taskSessions[task.id]?.close('Transfer inactivity timeout');
    });
  }

  bool _terminal(FileTransferTask task) => [
    TransferStatus.completed,
    TransferStatus.failed,
    TransferStatus.cancelled,
  ].contains(task.status);
  void _fail(FileTransferTask task, Object error) {
    if (_terminal(task)) return;
    task.status = TransferStatus.failed;
    task.errorMessage = error.toString();
    Logger('Diagnostics').warning(
      'transfer_failed reason=${error is FileSystemException
          ? 'disk_io'
          : error is FormatException
          ? 'protocol'
          : error is SocketException
          ? 'network'
          : error.toString() == 'Transfer inactivity timeout'
          ? 'timeout'
          : 'interrupted'}',
    );
    _timers.remove(task.id)?.cancel();
    _offers.remove(task.id);
    _update(task);
  }

  Future<FileTransferTask> sendFile({
    required String peerIp,
    required String peerId,
    int peerPort = defaultFileTransferPort,
    required String peerName,
    required File file,
    String? groupId,
  }) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final stat = await file.stat();
    final task = FileTransferTask(
      id: id,
      fileName: p.basename(file.path),
      filePath: file.path,
      fileSize: stat.size,
      isUpload: true,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
      groupId: groupId != null && groupIdPattern.hasMatch(groupId)
          ? groupId
          : null,
    );
    final random = Random.secure();
    final token = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final offer = {
      'id': id,
      'name': task.fileName,
      'token': token,
      'fields': [
        '$port',
        '${stat.size}',
        id,
        token,
        token,
        '',
        '0',
        '',
        '${stat.modified.toUtc().toIso8601String().split('.').first}Z',
        '',
        '0',
        '0',
        '-1',
        if (task.groupId != null) task.groupId!,
      ],
    };
    _tasks[id] = task;
    _offers[id] = offer;
    if (!isListening || !(sendOffer?.call(peerId, _packet(offer)) ?? false)) {
      _fail(task, 'Cannot send file offer: peer disconnected');
    } else {
      _timers[id] = Timer(
        const Duration(minutes: 5),
        () => _fail(task, 'File offer expired'),
      );
      _update(task);
    }
    return task;
  }

  void _upload(Socket socket) {
    FileTransferTask? task;
    RandomAccessFile? file;
    var endpoint = '', lastSent = 0;
    Future<void> queue = Future.value();
    late BeebeepSession session;
    session = BeebeepSession(
      socket,
      helloBuilder: (key) => helloBuilder!(key),
      password: passwordProvider?.call() ?? '',
      onMessage: (_) {},
      onHello: (hello) {
        endpoint = '${socket.remoteAddress.address}:${hello['port']}';
        if (!(isPeerConnected?.call(endpoint) ?? false)) {
          session.close('Unknown file peer');
        }
      },
      onData: (data) {
        queue = queue
            .then((_) async {
              if (task != null && _terminal(task!)) return;
              if (task == null) {
                final message = ProtocolBeebeep.parseMessage(utf8.decode(data));
                if (message == null) {
                  throw const FormatException('Invalid file request');
                }
                final request = parseOffer(message),
                    offer = _offers[parseOffer(message)['id']];
                final candidate = _tasks[request['id']];
                if (candidate == null ||
                    offer == null ||
                    candidate.peerId != endpoint ||
                    candidate.status != TransferStatus.pending ||
                    request['token'] != offer['token'] ||
                    request['name'] != offer['name']) {
                  throw const FormatException('Unauthorized file request');
                }
                task = candidate;
                _timers.remove(task!.id)?.cancel();
                _taskSessions[task!.id] = session;
                file = await File(task!.filePath).open();
                if (await file!.length() != task!.fileSize) {
                  throw const FileSystemException('File changed after offer');
                }
                task!.status = TransferStatus.transferring;
                if (!session.send(_packet(offer))) {
                  throw const SocketException('Header send failed');
                }
                _update(task!);
                return;
              }
              final ack = utf8
                  .decode(data)
                  .split(ProtocolBeebeep.dataFieldSeparator);
              if (ack.length < 3 ||
                  int.tryParse(ack[0]) != lastSent ||
                  int.tryParse(ack[1]) != task!.transferredBytes + lastSent ||
                  ack[2] != '1') {
                throw const FormatException('Invalid file confirmation');
              }
              task!.transferredBytes += lastSent;
              if (task!.transferredBytes == task!.fileSize) {
                task!.status = TransferStatus.completed;
                _offers.remove(task!.id);
                _update(task!);
                await socket.flush();
                session.close();
                return;
              }
              final chunk = await file!.read(
                min(65536, task!.fileSize - task!.transferredBytes),
              );
              if (chunk.isEmpty) {
                throw const FileSystemException('Unexpected file EOF');
              }
              lastSent = chunk.length;
              if (!session.send(chunk)) {
                throw const SocketException('File send failed');
              }
              _update(task!);
            })
            .catchError((Object e) {
              if (task != null) _fail(task!, e);
              session.close(e.toString());
            });
      },
      onClosed: () {
        _sessions.remove(session);
        if (task != null) {
          _taskSessions.remove(task!.id);
          // Drain the final ACK already queued before processing socket EOF.
        }
        unawaited(
          queue.then((_) async {
            if (task != null) {
              _fail(task!, session.error ?? 'Transfer disconnected');
            }
            await file?.close();
          }),
        );
      },
    );
    _sessions.add(session);
    session.start(outgoing: false);
  }

  Future<void> receiveOffer(
    String peerId,
    String peerIp,
    String peerName,
    Map<String, dynamic> message,
  ) async {
    Map<String, dynamic> offer;
    try {
      offer = parseOffer(message);
    } on FormatException {
      return;
    }
    final id = '$peerId/${offer['id']}';
    if ((message['flags'] as int) & 32 != 0) {
      final sent = _tasks[offer['id']];
      if (sent != null && sent.peerId == peerId) {
        _fail(sent, 'Receiver refused file');
      }
      return;
    }
    if (_tasks.containsKey(id) || !(isPeerConnected?.call(peerId) ?? false)) {
      return;
    }
    // Never interpret a remote name as a local path (including Windows ADS).
    var name = p
        .basename((offer['name'] as String).replaceAll('\\', '/'))
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '');
    if (name.isEmpty ||
        RegExp(
          r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(name)) {
      name = 'file_$name';
    }
    final task = FileTransferTask(
      id: id,
      fileName: name,
      filePath: '',
      fileSize: offer['size'] as int,
      isUpload: false,
      peerId: peerId,
      peerName: peerName,
      peerIp: peerIp,
      groupId: offer['groupId'] as String?,
    );
    _tasks[id] = task;
    _update(task);
    RandomAccessFile? file;
    BeebeepSession? session;
    Future<void> queue = Future.value();
    var headerReceived = false;
    String? finalPath;
    _watch(task);
    try {
      final folder = await Directory(
        await getDefaultDownloadDir(),
      ).createTemp('received_');
      finalPath = p.join(folder.path, name);
      task.filePath = '$finalPath.part';
      file = await File(task.filePath).open(mode: FileMode.write);
      final socket = await Socket.connect(
        peerIp,
        offer['port'] as int,
        timeout: const Duration(seconds: 5),
      );
      if (_terminal(task) || !isListening) {
        socket.destroy();
        await file.close();
        return;
      }
      session = BeebeepSession(
        socket,
        helloBuilder: (key) => helloBuilder!(key),
        password: passwordProvider?.call() ?? '',
        onMessage: (_) {},
        onHello: (hello) {
          if ('$peerIp:${hello['port']}' != peerId) {
            session!.close('Wrong file peer');
            return;
          }
          final fields = List<String>.from(offer['fields'] as List);
          while (fields.length < 13) {
            fields.add('');
          }
          fields[11] = '0';
          session!.send(_packet({...offer, 'fields': fields}));
        },
        onData: (data) {
          queue = queue
              .then((_) async {
                if (_terminal(task)) return;
                if (!headerReceived) {
                  final msg = ProtocolBeebeep.parseMessage(utf8.decode(data));
                  if (msg == null) {
                    throw const FormatException('Invalid file header');
                  }
                  final header = parseOffer(msg);
                  if (header['id'] != offer['id'] ||
                      header['size'] != task.fileSize ||
                      header['token'] != offer['token']) {
                    throw const FormatException('File header mismatch');
                  }
                  headerReceived = true;
                  task.status = TransferStatus.transferring;
                  if (task.fileSize > 0) session!.send(_ack(0, 0));
                } else {
                  if (task.transferredBytes + data.length > task.fileSize) {
                    throw const FormatException('File exceeds offered size');
                  }
                  await file!.writeFrom(data);
                  task.transferredBytes += data.length;
                  if (task.transferredBytes == task.fileSize) {
                    await file!.flush();
                  }
                  if (task.transferredBytes < task.fileSize &&
                      !session!.send(
                        _ack(data.length, task.transferredBytes),
                      )) {
                    throw const SocketException('Confirmation failed');
                  }
                }
                if (task.transferredBytes == task.fileSize) {
                  await file!.close();
                  file = null;
                  if (_terminal(task)) return;
                  if (await File(task.filePath).length() != task.fileSize) {
                    throw const FileSystemException('Downloaded size mismatch');
                  }
                  await File(task.filePath).rename(finalPath!);
                  task.filePath = finalPath;
                  if (!session!.send(
                    _ack(
                      task.fileSize == 0 ? 0 : data.length,
                      task.transferredBytes,
                    ),
                  )) {
                    throw const SocketException('Final confirmation failed');
                  }
                  task.status = TransferStatus.completed;
                  _update(task);
                  await socket.flush();
                  unawaited(socket.close());
                  return;
                }
                _update(task);
              })
              .catchError((Object e) {
                _fail(task, e);
                session!.close(e.toString());
              });
        },
        onClosed: () {
          _sessions.remove(session);
          _taskSessions.remove(id);
          unawaited(
            queue.then((_) async {
              _fail(task, session?.error ?? 'Transfer disconnected');
              await file?.close();
              file = null;
            }),
          );
        },
      );
      if (_terminal(task) || !isListening) {
        session.close();
        await file?.close();
        return;
      }
      _sessions.add(session);
      _taskSessions[id] = session;
      session.start(outgoing: true);
    } catch (e) {
      _fail(task, e);
      session?.close();
      await file?.close();
    }
  }

  void cancelTask(String id) {
    final task = _tasks[id];
    if (task == null || _terminal(task)) return;
    task.status = TransferStatus.cancelled;
    _offers.remove(id);
    _timers.remove(id)?.cancel();
    _taskSessions[id]?.close();
    _update(task);
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final task in _tasks.values) {
      cancelTask(task.id);
    }
    for (final session in _sessions.toList()) {
      session.close();
    }
    await server?.close();
  }
}
