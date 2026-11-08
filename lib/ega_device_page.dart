import 'dart:async';

import 'package:flutter/material.dart';

import 'com_host_service.dart';
import 'device_page.dart';
import 'ega_status.dart';

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
  final _statusController = TextEditingController(text: '等待设备主动推送 status…');
  StreamSubscription<ComHostMessage>? _statusSubscription;

  @override
  void initState() {
    super.initState();
    _statusSubscription = ComHostService.instance.messages.listen(
      _handleMessage,
      onError: _handleStreamError,
    );
  }

  void _handleMessage(ComHostMessage message) {
    if (message.id != EgaStatus.pushMessageId || message.isAck) return;
    try {
      final status = EgaStatus.fromBytes(message.data);
      if (mounted) setState(() => _statusController.text = status.format());
    } catch (error) {
      if (mounted) {
        setState(() => _statusController.text = 'status 解析失败：$error');
      }
    }
  }

  void _handleStreamError(Object error) {
    if (mounted) {
      setState(() => _statusController.text = 'status 接收失败：$error');
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('EGA Status', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _statusController,
            readOnly: true,
            expands: true,
            maxLines: null,
            minLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              labelText: '设备状态',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.all(12),
            ),
          ),
        ),
      ],
    ),
  );
}
