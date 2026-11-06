import 'dart:async';

import 'package:flutter/material.dart';

import 'ble_service.dart';
import 'com_host_service.dart';
import 'protocol_message_catalog.dart';

/// Base page for connected devices. Subclasses can add device-specific UI while
/// retaining the automatic 2 Hz, no-ACK com_host heartbeat.
class DevicePage extends StatefulWidget {
  const DevicePage({super.key});

  @override
  State<DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<DevicePage> {
  Timer? _pingTimer;
  MessageDefinition? _ping;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _startPings();
  }

  Future<void> _startPings() async {
    try {
      final catalog = await ProtocolMessageCatalog.load();
      if (!mounted || _leaving) return;
      _ping = catalog.byName('COM_HOST_MSG_ID_PING');
      _pingTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _sendPing(),
      );
      _sendPing();
    } catch (_) {
      // Keep the device page empty; a failed heartbeat does not alter the UI.
    }
  }

  void _sendPing() {
    final ping = _ping;
    if (ping == null || _leaving) return;
    try {
      ComHostService.instance.send(ping.id, ping.encodeData());
    } catch (_) {
      // The page stays empty; the next interval will retry.
    }
  }

  Future<void> _returnHome() async {
    if (_leaving) return;
    _leaving = true;
    _pingTimer?.cancel();
    await BleService.instance.disconnect();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _returnHome();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('设备页'),
        leading: IconButton(
          tooltip: '返回首页',
          onPressed: _returnHome,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: const SizedBox.expand(),
    ),
  );
}
