import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'com_host_service.dart';

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
      home: const ComHostTestPage(),
    );
  }
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
  String _sendStatus = '等待发送测试消息…';
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
    if (!mounted) return;
    try {
      final sequence = ComHostService.instance.send(
        0x00,
        Uint8List.fromList(const [0x00, 0x01, 0x02, 0x03]),
        needAck: true,
      );
      setState(() {
        _sendStatus = sequence < 0
            ? '发送失败，错误码：$sequence'
            : '已发送 msg_id=0x0000，序列号=$sequence，等待 ACK';
      });
    } catch (error) {
      setState(() => _sendStatus = '发送失败：$error');
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
