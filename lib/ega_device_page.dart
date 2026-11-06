import 'package:flutter/material.dart';

import 'com_host_service.dart';
import 'device_info.dart';
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
      final info = DeviceInfo.fromBytes(ack.data);
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
