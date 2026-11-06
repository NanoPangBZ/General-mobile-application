import 'dart:async';
import 'dart:collection';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

typedef TransportWrite = Future<void> Function(Uint8List bytes);

class ComHostMessage {
  const ComHostMessage({
    required this.id,
    required this.sender,
    required this.sequence,
    required this.needsAck,
    required this.isAck,
    required this.data,
  });

  final int id;
  final int sender;
  final int sequence;
  final bool needsAck;
  final bool isAck;
  final Uint8List data;
}

/// One native host, one port and one route for the entire app process.
/// Call every method from the main Dart isolate.
class ComHostService {
  ComHostService._() : _native = _NativeHost();

  static final ComHostService instance = ComHostService._();
  final _NativeHost _native;
  final _messages = StreamController<ComHostMessage>.broadcast();
  final _outgoingBytes = StreamController<Uint8List>.broadcast();
  final Queue<Uint8List> _pendingOutput = Queue<Uint8List>();
  TransportWrite? _write;
  StreamSubscription<Uint8List>? _inputSubscription;
  Timer? _poller;
  bool _writing = false;

  Stream<ComHostMessage> get messages => _messages.stream;
  Stream<Uint8List> get outgoingBytes => _outgoingBytes.stream;
  bool get hasTransport => _inputSubscription != null;
  int get droppedOutput => _native.droppedOutput();
  int get droppedMessages => _native.droppedMessages();

  void initialize() {
    final result = _native.init();
    if (result != 0) throw StateError('com_host init failed: $result');
    _poller ??= Timer.periodic(const Duration(milliseconds: 10), (_) => _drain());
  }

  /// Attach exactly one byte transport. Its incoming chunks may have any size.
  void attachTransport(Stream<Uint8List> incoming, TransportWrite write) {
    if (_poller == null) throw StateError('Call initialize first');
    if (_write != null) throw StateError('Transport is already attached');
    _write = write;
    _inputSubscription = incoming.listen(feed, onError: _messages.addError);
    _drain();
  }

  /// Send a protocol message to COM_HOST_ID_MAIN_CONTROLLER (0x01).
  /// Returns its sequence number, or a negative error code.
  int send(int messageId, Uint8List data, {bool needAck = false}) {
    if (messageId < 0 || messageId > 0xffff || data.length > _native.capacity) {
      throw RangeError('Message id or payload exceeds native capacity');
    }
    _native.buffer.asTypedList(data.length).setAll(0, data);
    final result = _native.send(messageId, data.length, needAck ? 1 : 0);
    _drain();
    return result;
  }

  /// Reply to a received request using its sender, id and sequence.
  int sendAck(ComHostMessage request, Uint8List data) {
    if (request.isAck || !request.needsAck || data.isEmpty || data.length > _native.capacity) {
      throw ArgumentError('Invalid ACK request or payload');
    }
    _native.buffer.asTypedList(data.length).setAll(0, data);
    final result = _native.sendAck(request.sender, request.id, request.sequence, data.length);
    _drain();
    return result;
  }

  /// Supply raw bytes from BLE, USB or another transport to the one port.
  void feed(Uint8List bytes) {
    if (_poller == null) throw StateError('Call initialize first');
    for (var offset = 0; offset < bytes.length; offset += _native.capacity) {
      final end = offset + _native.capacity < bytes.length
          ? offset + _native.capacity
          : bytes.length;
      _native.buffer.asTypedList(end - offset).setAll(0, bytes.sublist(offset, end));
      final result = _native.feed(end - offset);
      if (result != 0) throw StateError('com_host input failed: $result');
    }
    _drain();
  }

  void _drain() {
    if (_poller == null) return;
    while (true) {
      final encodedLength = _native.takeMessage();
      if (encodedLength == 0) break;
      final length = encodedLength - 1;
      _messages.add(ComHostMessage(
        id: _native.messageId(),
        sender: _native.messageSender(),
        sequence: _native.messageSeq(),
        needsAck: _native.messageNeedsAck() != 0,
        isAck: _native.messageIsAck() != 0,
        data: Uint8List.fromList(_native.buffer.asTypedList(length)),
      ));
    }
    while (true) {
      final length = _native.takeOutput();
      if (length == 0) break;
      final bytes = Uint8List.fromList(_native.buffer.asTypedList(length));
      _outgoingBytes.add(bytes);
      if (_write != null) _pendingOutput.add(bytes);
    }
    if (_write != null && !_writing) unawaited(_flushOutput());
  }

  Future<void> _flushOutput() async {
    _writing = true;
    try {
      while (_pendingOutput.isNotEmpty) {
        await _write!(_pendingOutput.first);
        _pendingOutput.removeFirst();
      }
    } catch (error, stack) {
      _messages.addError(error, stack);
    } finally {
      _writing = false;
    }
  }
}

class _NativeHost {
  _NativeHost() {
    final library = Platform.isAndroid
        ? DynamicLibrary.open('libcom_host_bridge.so')
        : Platform.isIOS
            ? DynamicLibrary.process()
            : throw UnsupportedError('com_host supports Android and iOS only');
    init = library.lookupFunction<Int32 Function(), int Function()>('mobile_host_init');
    final bufferFn = library.lookupFunction<Pointer<Uint8> Function(), Pointer<Uint8> Function()>('mobile_host_buffer');
    buffer = bufferFn();
    final capacityFn = library.lookupFunction<Uint32 Function(), int Function()>('mobile_host_buffer_capacity');
    capacity = capacityFn();
    send = library.lookupFunction<Int32 Function(Uint16, Uint16, Uint8), int Function(int, int, int)>('mobile_host_send');
    sendAck = library.lookupFunction<Int32 Function(Uint8, Uint16, Uint8, Uint16), int Function(int, int, int, int)>('mobile_host_send_ack');
    feed = library.lookupFunction<Int32 Function(Uint32), int Function(int)>('mobile_host_feed');
    takeOutput = library.lookupFunction<Int32 Function(), int Function()>('mobile_host_take_output');
    takeMessage = library.lookupFunction<Int32 Function(), int Function()>('mobile_host_take_message');
    messageId = library.lookupFunction<Uint16 Function(), int Function()>('mobile_host_message_id');
    messageSender = library.lookupFunction<Uint8 Function(), int Function()>('mobile_host_message_sender');
    messageSeq = library.lookupFunction<Uint8 Function(), int Function()>('mobile_host_message_seq');
    messageNeedsAck = library.lookupFunction<Uint8 Function(), int Function()>('mobile_host_message_need_ack');
    messageIsAck = library.lookupFunction<Uint8 Function(), int Function()>('mobile_host_message_is_ack');
    droppedOutput = library.lookupFunction<Uint32 Function(), int Function()>('mobile_host_dropped_output');
    droppedMessages = library.lookupFunction<Uint32 Function(), int Function()>('mobile_host_dropped_messages');
  }

  late final int Function() init;
  late final Pointer<Uint8> buffer;
  late final int capacity;
  late final int Function(int, int, int) send;
  late final int Function(int, int, int, int) sendAck;
  late final int Function(int) feed;
  late final int Function() takeOutput;
  late final int Function() takeMessage;
  late final int Function() messageId;
  late final int Function() messageSender;
  late final int Function() messageSeq;
  late final int Function() messageNeedsAck;
  late final int Function() messageIsAck;
  late final int Function() droppedOutput;
  late final int Function() droppedMessages;
}
