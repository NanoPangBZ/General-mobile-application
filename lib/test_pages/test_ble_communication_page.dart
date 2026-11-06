import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble_service.dart';
import '../com_host_service.dart';
import '../device_info.dart';
import '../protocol_message_catalog.dart';

class TestBleCommunicationPage extends StatefulWidget {
  const TestBleCommunicationPage({
    required this.device,
    required this.services,
    super.key,
  });

  final BluetoothDevice device;
  final List<BluetoothService> services;

  @override
  State<TestBleCommunicationPage> createState() =>
      _TestBleCommunicationPageState();
}

class _TestBleCommunicationPageState extends State<TestBleCommunicationPage> {
  final _ble = BleService.instance;
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _log = [];
  BluetoothCharacteristic? _receive;
  BluetoothCharacteristic? _transmit;
  StreamSubscription<List<int>>? _incomingSubscription;
  bool _sending = false;
  bool _pinging = false;
  bool _queryingDeviceInfo = false;
  String? _error;

  List<BluetoothCharacteristic> get _characteristics => widget.services
      .expand((service) => service.characteristics)
      .toList(growable: false);

  List<BluetoothCharacteristic> get _receivable => _characteristics
      .where((c) => c.properties.notify || c.properties.indicate)
      .toList(growable: false);

  List<BluetoothCharacteristic> get _writable => _characteristics
      .where((c) => c.properties.write || c.properties.writeWithoutResponse)
      .toList(growable: false);

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _label(BluetoothCharacteristic characteristic) =>
      '${characteristic.serviceUuid.str} / ${characteristic.characteristicUuid.str}';

  Future<void> _configure() async {
    await _incomingSubscription?.cancel();
    _incomingSubscription = null;
    if (_receive == null || _transmit == null) return;
    try {
      await _ble.configureTransport(receive: _receive!, transmit: _transmit!);
      _incomingSubscription = _ble.listenIncoming((bytes) {
        _append('RX', bytes);
      });
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = '配置特征值失败：$error');
    }
  }

  Uint8List _parseHex(String input) {
    final normalized = input
        .replaceAll(RegExp(r'0x', caseSensitive: false), '')
        .replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (normalized.isEmpty) throw const FormatException('请输入十六进制数据');
    if (normalized.length.isOdd) throw const FormatException('十六进制字符数必须为偶数');
    return Uint8List.fromList(
      List.generate(
        normalized.length ~/ 2,
        (index) => int.parse(
          normalized.substring(index * 2, index * 2 + 2),
          radix: 16,
        ),
      ),
    );
  }

  Future<void> _send() async {
    if (_transmit == null) {
      setState(() => _error = '请先选择 TX 写入特征值');
      return;
    }
    try {
      final bytes = _parseHex(_inputController.text);
      setState(() {
        _sending = true;
        _error = null;
      });
      await _ble.write(bytes);
      _append('TX', bytes);
      _inputController.clear();
    } catch (error) {
      if (mounted) setState(() => _error = '发送失败：$error');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendPing() async {
    if (!_ble.isConnected || !_ble.transportConfigured) {
      setState(() => _error = '请先配置 BLE RX/TX 特征值');
      return;
    }
    setState(() {
      _pinging = true;
      _error = null;
    });
    try {
      final catalog = await ProtocolMessageCatalog.load();
      final ping = catalog.byName('COM_HOST_MSG_ID_PING');
      final ack = await ComHostService.instance.sendAndWaitAck(
        ping.id,
        ping.encodeData(),
      );
      final decoded = ping.decodeAck(ack.data);
      _append('PING ACK', Uint8List.fromList(ack.data));
      if (mounted) {
        setState(
          () => _error =
              'Ping 成功：运行时间 ${decoded['uptime']} 秒，保留字段 ${decoded['rsvd']}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Ping 失败：$error');
    } finally {
      if (mounted) setState(() => _pinging = false);
    }
  }

  Future<void> _queryDeviceInfo() async {
    if (!_ble.isConnected || !_ble.transportConfigured) {
      setState(() => _error = '请先配置 BLE RX/TX 特征值');
      return;
    }
    setState(() {
      _queryingDeviceInfo = true;
      _error = null;
    });
    try {
      final catalog = await ProtocolMessageCatalog.load();
      final request = catalog.byName('COM_HOST_MSG_ID_REQ_DEVICE_INFO');
      final ack = await ComHostService.instance.sendAndWaitAck(
        request.id,
        request.encodeData(),
      );
      final info = DeviceInfo.fromBytes(ack.data);
      _append('DEVICE INFO ACK', ack.data);
      _appendText('设备信息', info.format());
    } catch (error) {
      if (mounted) setState(() => _error = '设备信息查询失败：$error');
    } finally {
      if (mounted) setState(() => _queryingDeviceInfo = false);
    }
  }

  void _append(String direction, Uint8List bytes) {
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    if (!mounted) return;
    setState(
      () => _log.add('$direction  ${DateTime.now().toIso8601String()}\n$hex'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void _appendText(String title, String text) {
    if (!mounted) return;
    setState(
      () => _log.add('$title  ${DateTime.now().toIso8601String()}\n$text'),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.device.platformName.isEmpty
            ? 'BLE 通信'
            : '${widget.device.platformName} 通信',
      ),
      actions: [
        IconButton(
          tooltip: '断开连接',
          icon: const Icon(Icons.link_off),
          onPressed: () async {
            await _ble.disconnect();
            if (!mounted) return;
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Column(
              children: [
                DropdownButtonFormField<BluetoothCharacteristic>(
                  initialValue: _receive,
                  decoration: const InputDecoration(
                    labelText: 'RX 接收特征值（Notify / Indicate）',
                  ),
                  items: _receivable
                      .map(
                        (characteristic) => DropdownMenuItem(
                          value: characteristic,
                          child: Text(
                            _label(characteristic),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _receive = value);
                    _configure();
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<BluetoothCharacteristic>(
                  initialValue: _transmit,
                  decoration: const InputDecoration(
                    labelText: 'TX 发送特征值（Write）',
                  ),
                  items: _writable
                      .map(
                        (characteristic) => DropdownMenuItem(
                          value: characteristic,
                          child: Text(
                            _label(characteristic),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() => _transmit = value);
                    _configure();
                  },
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: _log.isEmpty
                ? const Center(child: Text('选择 RX/TX 特征值后开始通信'))
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    itemCount: _log.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _log[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: '发送十六进制数据',
                      hintText: '例如：AA 01 0F',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.send),
                  label: Text(_sending ? '发送中' : '发送'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pinging || !_ble.transportConfigured
                        ? null
                        : _sendPing,
                    icon: const Icon(Icons.network_ping),
                    label: Text(_pinging ? 'Ping 等待应答…' : 'com_host Ping'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _queryingDeviceInfo || !_ble.transportConfigured
                        ? null
                        : _queryDeviceInfo,
                    icon: const Icon(Icons.info_outline),
                    label: Text(_queryingDeviceInfo ? '查询中…' : '查询设备信息'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
