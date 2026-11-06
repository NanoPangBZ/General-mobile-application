import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'com_host_service.dart';
import 'ble_device_page.dart';
import 'protocol_message_catalog.dart';

void main() {
  ComHostService.instance.initialize();
  runApp(const DeveloperApp());
}

class DeveloperApp extends StatelessWidget {
  const DeveloperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'developer-app',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Developer App'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.cable), text: 'com_host'),
                Tab(icon: Icon(Icons.bluetooth), text: 'BLE 设备'),
              ],
            ),
          ),
          body: const TabBarView(
            children: [
              ComHostTestPage(),
              BleDevicePage(),
            ],
          ),
        ),
      );
}

class ComHostTestPage extends StatefulWidget {
  const ComHostTestPage({super.key});

  @override
  State<ComHostTestPage> createState() => _ComHostTestPageState();
}

class _ComHostTestPageState extends State<ComHostTestPage> {
  final _outputController = TextEditingController();
  StreamSubscription<Uint8List>? _outputSubscription;
  Timer? _sendTimer;
  String _sendStatus = '等待发送 Ping 测试…';
  int _frameCount = 0;

  @override
  void initState() {
    super.initState();
    _outputSubscription = ComHostService.instance.outgoingBytes.listen(_showFrame);
    _sendTimer = Timer(const Duration(seconds: 2), _sendTestMessage);
  }

  void _showFrame(Uint8List bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    setState(() {
      _frameCount++;
      final prefix = _outputController.text.isEmpty ? '' : '\n';
      _outputController.text = '${_outputController.text}$prefix$hex';
    });
  }

  void _sendTestMessage() {
    unawaited(_sendPing());
  }

  Future<void> _sendPing() async {
    if (!mounted) return;
    try {
      final catalog = await ProtocolMessageCatalog.load();
      final ping = catalog.byName('COM_HOST_MSG_ID_PING');
      final payload = ping.encodeData();
      setState(() {
        _sendStatus = '发送 ${ping.name} (${ping.brief})，等待 MainController 应答…';
      });
      final ack = await ComHostService.instance.sendAndWaitAck(ping.id, payload);
      final decoded = ping.decodeAck(ack.data);
      if (!mounted) return;
      setState(() {
        _sendStatus = '收到 Ping 应答，序列号=${ack.sequence}，'
            '运行时间=${decoded['uptime']} 秒，保留字段=${decoded['rsvd']}';
      });
    } catch (error) {
      if (mounted) setState(() => _sendStatus = 'Ping 测试失败：$error');
    }
  }

  @override
  void dispose() {
    _sendTimer?.cancel();
    _outputSubscription?.cancel();
    _outputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('com_host 测试')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_sendStatus),
              const SizedBox(height: 8),
              Text('Port.write 输出 · $_frameCount 帧'),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _outputController,
                  readOnly: true,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: '等待 com_host port 写出数据…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
