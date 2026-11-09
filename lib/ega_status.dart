import 'dart:typed_data';

/// EGA private status pushed by the device without a subscription request.
class EgaStatus {
  const EgaStatus({
    required this.bleEnabled,
    required this.bleConnected,
    required this.uhfEnabled,
    required this.uhfConnected,
    required this.batteryPercent,
    required this.batteryCharging,
    required this.usbConnected,
    required this.currentPresetDirty,
    required this.currentPresetIndex,
    required this.cpuLoad,
    required this.drummerPlaying,
    required this.drummerVolume,
    required this.drummerType,
    required this.bpmRaw,
  });

  static const int subscriptionMessageId = 0x0220;
  static const int pushMessageId = 0x0221;
  static const int pushCycleMs = 500;
  static const int payloadLength = 8;

  /// subscribe=1, notify_on_change=1, push_cycle_ms=500, reserved=0.
  static Uint8List buildSubscriptionPayload() {
    final data = ByteData(5);
    data.setUint8(0, 0x03);
    data.setUint16(1, pushCycleMs, Endian.little);
    return data.buffer.asUint8List();
  }

  final bool bleEnabled;
  final bool bleConnected;
  final bool uhfEnabled;
  final bool uhfConnected;
  final int batteryPercent;
  final bool batteryCharging;
  final bool usbConnected;
  final bool currentPresetDirty;
  final int currentPresetIndex;
  final int cpuLoad;
  final bool drummerPlaying;
  final int drummerVolume;
  final int drummerType;
  final int bpmRaw;

  factory EgaStatus.fromBytes(Uint8List bytes) {
    if (bytes.length != payloadLength) {
      throw FormatException(
        'EGA status 长度错误，期望 $payloadLength 字节，实际 ${bytes.length} 字节',
      );
    }
    final data = ByteData.sublistView(bytes);
    final first = data.getUint32(0, Endian.little);
    final second = data.getUint32(4, Endian.little);
    return EgaStatus(
      bleEnabled: _bit(first, 0),
      bleConnected: _bit(first, 1),
      uhfEnabled: _bit(first, 2),
      uhfConnected: _bit(first, 3),
      batteryPercent: (first >> 4) & 0x7f,
      batteryCharging: _bit(first, 11),
      usbConnected: _bit(first, 12),
      currentPresetDirty: _bit(first, 13),
      currentPresetIndex: (first >> 14) & 0x1f,
      cpuLoad: (first >> 19) & 0x03,
      drummerPlaying: _bit(first, 21),
      drummerVolume: (first >> 22) & 0x7f,
      drummerType: second & 0x3f,
      bpmRaw: (second >> 6) & 0xff,
    );
  }

  static bool _bit(int value, int offset) => value & (1 << offset) != 0;

  String format() => [
    'BLE：${_enabled(bleEnabled)}，${_connected(bleConnected)}',
    'UHF：${_enabled(uhfEnabled)}，${_connected(uhfConnected)}',
    '电池：$batteryPercent%${batteryCharging ? '（充电中）' : ''}',
    'USB：${_connected(usbConnected)}',
    '当前预设：${_indexedValue(currentPresetIndex, 20)}'
        '${currentPresetDirty ? '（未保存）' : ''}',
    'CPU 负载：${_cpuLoadName(cpuLoad)}',
    '鼓机：${drummerPlaying ? '演奏中' : '停止'}',
    '鼓机音量：$drummerVolume%',
    '鼓机类型：${_indexedValue(drummerType, 20)}',
    'BPM：${bpmRaw <= 220 ? bpmRaw + 40 : '无效（raw: $bpmRaw）'}',
  ].join('\n');

  static String _enabled(bool value) => value ? '启用' : '未启用';

  static String _connected(bool value) => value ? '已连接' : '未连接';

  static String _indexedValue(int value, int max) =>
      value >= 1 && value <= max ? '$value' : '无效（$value）';

  static String _cpuLoadName(int value) => switch (value) {
    0 => '轻',
    1 => '一般',
    2 => '较大',
    3 => '紧急',
    _ => '未知',
  };
}
