import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'com_host_service.dart';
import 'device_page.dart';
import 'protocol_message_catalog.dart';

/// EGA guitar amplifier page, sharing the base device connection lifecycle.
class EgaDevicePage extends DevicePage {
  const EgaDevicePage({super.key});

  @override
  String get pageTitle => '电吉他音箱';

  @override
  Widget buildDeviceContent(BuildContext context) => const _EgaDeviceContent();
}

class _EgaDeviceContent extends StatefulWidget {
  const _EgaDeviceContent();

  @override
  State<_EgaDeviceContent> createState() => _EgaDeviceContentState();
}

class _EgaDeviceContentState extends State<_EgaDeviceContent> {
  final _deviceInfoController = TextEditingController(text: '点击“测试”获取设备信息');
  bool _requesting = false;

  void _showDeviceInfo(String text) {
    _deviceInfoController.text = text;
  }

  Future<void> _requestDeviceInfo() async {
    if (_requesting) return;
    setState(() {
      _requesting = true;
      _showDeviceInfo('正在获取设备信息…');
    });

    try {
      final catalog = await ProtocolMessageCatalog.load();
      final request = catalog.byName('COM_HOST_MSG_ID_REQ_DEVICE_INFO');
      final ack = await ComHostService.instance.sendAndWaitAck(
        request.id,
        request.encodeData(),
      );
      final info = _DeviceInfo.fromBytes(ack.data);
      if (mounted) setState(() => _showDeviceInfo(info.format()));
    } catch (error) {
      if (mounted) setState(() => _showDeviceInfo('获取失败：$error'));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  void dispose() {
    _deviceInfoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: _requesting ? null : _requestDeviceInfo,
          child: Text(_requesting ? '获取中…' : '测试'),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: TextField(
            controller: _deviceInfoController,
            readOnly: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: '设备信息',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    ),
  );
}

class _DeviceInfo {
  const _DeviceInfo({
    required this.result,
    required this.architecture,
    required this.deviceName,
    required this.hardwareVersion,
    required this.firmwareVersion,
    required this.buildDate,
    required this.isReleased,
    required this.isDemo,
    required this.gitBranch,
    required this.gitCommitHash,
    required this.gitCommitDate,
    required this.boardName,
    required this.brief,
  });

  static const int _fixedLength = 121;

  final int result;
  final int architecture;
  final String deviceName;
  final String hardwareVersion;
  final String firmwareVersion;
  final String buildDate;
  final bool isReleased;
  final bool isDemo;
  final String gitBranch;
  final String gitCommitHash;
  final String gitCommitDate;
  final String boardName;
  final String brief;

  factory _DeviceInfo.fromBytes(Uint8List bytes) {
    if (bytes.length < _fixedLength) {
      throw FormatException(
        '设备信息长度不足，期望至少 $_fixedLength 字节，实际 ${bytes.length} 字节',
      );
    }
    final data = ByteData.sublistView(bytes);
    final briefLength = data.getUint16(119, Endian.little);
    if (briefLength > bytes.length - _fixedLength) {
      throw FormatException(
        '设备简要信息长度无效：$briefLength（剩余 ${bytes.length - _fixedLength} 字节）',
      );
    }
    final flags = bytes[47];
    return _DeviceInfo(
      result: bytes[0],
      architecture: bytes[1],
      deviceName: _readText(bytes, 2, 32),
      hardwareVersion: _readVersion(bytes, 34),
      firmwareVersion: _readVersion(bytes, 37),
      buildDate: _readDateTime(bytes, 40),
      isReleased: flags & 0x01 != 0,
      isDemo: flags & 0x02 != 0,
      gitBranch: _readText(bytes, 48, 16),
      gitCommitHash: _readText(bytes, 64, 16),
      gitCommitDate: _readDateTime(bytes, 80),
      boardName: _readText(bytes, 87, 32),
      brief: _readText(bytes, _fixedLength, briefLength),
    );
  }

  static String _readText(Uint8List bytes, int offset, int length) {
    final field = bytes.sublist(offset, offset + length);
    final terminator = field.indexOf(0);
    return utf8.decode(
      terminator < 0 ? field : field.sublist(0, terminator),
      allowMalformed: true,
    );
  }

  static String _readVersion(Uint8List bytes, int offset) =>
      '${bytes[offset]}.${bytes[offset + 1]}.${bytes[offset + 2]}';

  static String _readDateTime(Uint8List bytes, int offset) {
    final data = ByteData.sublistView(bytes);
    final year = data.getUint16(offset, Endian.little);
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '$year-${twoDigits(bytes[offset + 2])}-${twoDigits(bytes[offset + 3])} '
        '${twoDigits(bytes[offset + 4])}:${twoDigits(bytes[offset + 5])}:'
        '${twoDigits(bytes[offset + 6])}';
  }

  String format() => [
    '请求结果：${_resultName(result)} ($result)',
    '架构：${_architectureName(architecture)} ($architecture)',
    '设备名称：$deviceName',
    '硬件版本：$hardwareVersion',
    '固件版本：$firmwareVersion',
    '编译时间：$buildDate',
    '发布版本：${isReleased ? '是' : '否'}',
    '演示版本：${isDemo ? '是' : '否'}',
    'Git 分支：$gitBranch',
    'Git 提交：$gitCommitHash',
    'Git 提交时间：$gitCommitDate',
    '板卡名称：$boardName',
    '简要信息：$brief',
  ].join('\n');

  static String _resultName(int value) => switch (value) {
    0 => '成功',
    1 => '错误',
    2 => '超时',
    3 => '未找到',
    4 => '忙碌',
    5 => '无效',
    6 => '权限不足',
    7 => '状态错误',
    8 => '内存不足',
    9 => '已锁定',
    _ => '未知',
  };

  static String _architectureName(int value) => switch (value) {
    0 => 'ARM Cortex-M',
    1 => 'ARM Cortex-A',
    2 => 'ARM Cortex-R',
    3 => 'ARM 64 位',
    4 => 'X86',
    5 => 'RISC-V',
    6 => 'MIPS',
    _ => '未知',
  };
}
