import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble_service.dart';
import 'test_ble_communication_page.dart';

class TestBleDevicePage extends StatefulWidget {
  const TestBleDevicePage({super.key});

  @override
  State<TestBleDevicePage> createState() => _TestBleDevicePageState();
}

class _TestBleDevicePageState extends State<TestBleDevicePage> {
  final _ble = BleService.instance;
  StreamSubscription<List<ScanResult>>? _resultsSubscription;
  List<ScanResult> _results = [];
  String _status = '蓝牙未连接';
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _resultsSubscription = _ble.scanResults.listen((results) {
      if (mounted) setState(() => _results = results);
    });
  }

  Future<void> _scan() async {
    try {
      if (!await _ble.isSupported) throw StateError('设备不支持蓝牙');
      setState(() {
        _scanning = true;
        _status = '正在扫描…';
        _results = [];
      });
      await _ble.startScan();
      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      if (mounted) setState(() => _status = '扫描完成：发现 ${_results.length} 台设备');
    } catch (error) {
      if (mounted) setState(() => _status = '扫描失败：$error');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _status = '正在连接 ${device.platformName}…');
    try {
      final services = await _ble.connect(device);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TestBleCommunicationPage(device: device, services: services),
        ),
      );
      if (mounted) setState(() => _status = '已断开连接');
    } catch (error) {
      if (mounted) setState(() => _status = '连接失败：$error');
    }
  }

  @override
  void dispose() {
    _resultsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: Text(_status)),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching),
              label: Text(_scanning ? '扫描中' : '扫描'),
            ),
          ],
        ),
      ),
      Expanded(
        child: _results.isEmpty
            ? const Center(child: Text('扫描附近的 BLE 外设'))
            : ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  final name = result.advertisementData.advName.isNotEmpty
                      ? result.advertisementData.advName
                      : result.device.platformName;
                  final manufacturerData =
                      result.advertisementData.manufacturerData;
                  final manufacturerText = manufacturerData.entries
                      .map(
                        (entry) =>
                            '${entry.key.toRadixString(16).padLeft(4, '0').toUpperCase()}: '
                            '${entry.value.map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ')}',
                      )
                      .join('\n');
                  return ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(name.isEmpty ? '未命名设备' : name),
                    subtitle: manufacturerText.isEmpty
                        ? Text('RSSI ${result.rssi} dBm')
                        : Text('厂商数据：\n$manufacturerText'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _connect(result.device),
                  );
                },
              ),
      ),
    ],
  );
}
