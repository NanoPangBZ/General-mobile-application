import 'dart:async';

import 'package:flutter/foundation.dart';

import '../com_host_service.dart';

/// In-memory application log. It only subscribes to messages delivered to
/// Flutter by com_host; framework and native library logs are not collected.
class TestAppLogService extends ChangeNotifier {
  TestAppLogService._() {
    _subscription = ComHostService.instance.messages.listen(_recordMessage);
    _nativeLogSubscription = ComHostService.instance.nativeLogs.listen(
      _recordNativeLog,
    );
  }

  static final TestAppLogService instance = TestAppLogService._();
  static const int maxEntries = 500;

  final List<TestAppLogEntry> _entries = <TestAppLogEntry>[];
  late final StreamSubscription<ComHostMessage> _subscription;
  late final StreamSubscription<ComHostNativeLog> _nativeLogSubscription;

  List<TestAppLogEntry> get entries => List.unmodifiable(_entries);

  void _recordMessage(ComHostMessage message) {
    _entries.insert(0, TestAppLogEntry.fromMessage(message));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  void _recordNativeLog(ComHostNativeLog log) {
    _entries.insert(0, TestAppLogEntry.fromNativeLog(log));
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    _nativeLogSubscription.cancel();
    super.dispose();
  }
}

class TestAppLogEntry {
  const TestAppLogEntry({
    required this.time,
    required this.messageId,
    required this.sender,
    required this.sequence,
    required this.needsAck,
    required this.isAck,
    required this.dataLength,
    required this.dataHex,
    required this.source,
    required this.level,
    required this.text,
  });

  factory TestAppLogEntry.fromMessage(ComHostMessage message) =>
      TestAppLogEntry(
        time: DateTime.now(),
        messageId: message.id,
        sender: message.sender,
        sequence: message.sequence,
        needsAck: message.needsAck,
        isAck: message.isAck,
        dataLength: message.data.length,
        dataHex: message.dataHex,
        source: 'com_host MSG',
        level: null,
        text: null,
      );

  factory TestAppLogEntry.fromNativeLog(ComHostNativeLog log) =>
      TestAppLogEntry(
        time: DateTime.now(),
        messageId: 0,
        sender: 0,
        sequence: 0,
        needsAck: false,
        isAck: false,
        dataLength: 0,
        dataHex: '',
        source: 'com_host native',
        level: log.level,
        text: log.text,
      );

  final DateTime time;
  final int messageId;
  final int sender;
  final int sequence;
  final bool needsAck;
  final bool isAck;
  final int dataLength;
  final String dataHex;
  final String source;
  final int? level;
  final String? text;

  String get formattedTime {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.${three(time.millisecond)}';
  }
}
