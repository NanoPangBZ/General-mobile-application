import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'dart:ui' as ui;

import 'ble_service.dart';
import 'device_page.dart';
import 'ega_device_page.dart';
import 'com_host_service.dart';
import 'device_description.dart';
import 'protocol_message_catalog.dart';
import 'test_pages/test_developer_tools_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
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

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ble = BleService.instance;
  static const _tapWindow = Duration(seconds: 3);
  int _cornerTapCount = 0;
  Timer? _cornerTapTimer;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<bool>? _scanningSubscription;
  final List<ScanResult> _matchingDevices = [];
  final Map<String, DateTime> _lastSeen = {};
  Timer? _presenceTimer;
  bool _scanning = false;
  String? _scanError;
  String? _connectingDeviceId;

  @override
  void initState() {
    super.initState();
    _scanResultsSubscription = _ble.scanResults.listen(
      _updateDevices,
      onError: (Object error) {
        if (mounted) setState(() => _scanError = error.toString());
      },
    );
    _scanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _scanning = scanning);
    });
    _presenceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && _matchingDevices.isNotEmpty) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scanForConfiguredDevices(),
    );
  }

  void _updateDevices(List<ScanResult> results) {
    for (final result in results) {
      final name = result.advertisementData.advName.isNotEmpty
          ? result.advertisementData.advName
          : result.device.platformName;
      if (deviceDescriptions.devices.any((device) => device.matches(name))) {
        final index = _matchingDevices.indexWhere(
          (existing) =>
              existing.device.remoteId.str == result.device.remoteId.str,
        );
        if (index == -1) {
          _matchingDevices.add(result);
        } else {
          _matchingDevices[index] = result;
        }
        _lastSeen[result.device.remoteId.str] = result.timeStamp;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _scanForConfiguredDevices() async {
    try {
      if (!await _ble.isSupported) {
        if (mounted) setState(() => _scanError = '此设备不支持蓝牙');
        return;
      }
      await _ble.startScan(timeout: null, continuousUpdates: true);
    } catch (error) {
      if (mounted) setState(() => _scanError = '无法扫描 BLE 设备：$error');
    }
  }

  void _handleCornerTap() {
    _cornerTapTimer?.cancel();
    _cornerTapCount++;
    if (_cornerTapCount >= 5) {
      _cornerTapCount = 0;
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TestDeveloperToolsPage()),
      );
      return;
    }
    _cornerTapTimer = Timer(_tapWindow, () => _cornerTapCount = 0);
  }

  Widget _buildScanStatus() {
    final text = _scanError ?? (_scanning ? '正在搜索已配置的 BLE 设备…' : '附近没有已配置的设备');
    return Card(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.88),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_scanning && _scanError == null) ...[
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(child: Text(text, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(ScanResult result) {
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : result.device.platformName;
    final description = deviceDescriptions.devices.firstWhere(
      (device) => device.matches(name),
    );
    final isOnline =
        _lastSeen[result.device.remoteId.str]?.isAfter(
          DateTime.now().subtract(const Duration(seconds: 2)),
        ) ??
        false;
    return Card(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
      child: ListTile(
        leading: _connectingDeviceId == result.device.remoteId.str
            ? const SizedBox(
                width: 40,
                height: 40,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : const CircleAvatar(child: Icon(Icons.speaker)),
        title: Text(description.productName),
        subtitle: Text(
          _connectingDeviceId == result.device.remoteId.str
              ? '正在连接并验证 Ping…'
              : 'BLE · $name',
        ),
        onTap: _connectingDeviceId == null
            ? () => _connectAndValidate(result, description)
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${result.rssi} dBm'),
            const SizedBox(width: 12),
            Tooltip(
              message: isOnline ? '在线' : '已消失',
              child: Icon(
                Icons.circle,
                size: 12,
                color: isOnline ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectAndValidate(
    ScanResult result,
    DeviceDescription description,
  ) async {
    final deviceId = result.device.remoteId.str;
    setState(() => _connectingDeviceId = deviceId);
    try {
      await _ble.stopScan();
      final services = await _ble.connect(result.device);
      await _ble.configureFromDeviceDescription(
        services: services,
        description: description,
      );
      final catalog = await ProtocolMessageCatalog.load();
      final ping = catalog.byName('COM_HOST_MSG_ID_PING');
      ComHostMessage? ack;
      for (var attempt = 1; attempt <= description.pingAttempts; attempt++) {
        try {
          ack = await ComHostService.instance.sendAndWaitAck(
            ping.id,
            ping.encodeData(),
            timeout: Duration(milliseconds: description.pingTimeoutMs),
          );
          break;
        } catch (error) {
          if (attempt < description.pingAttempts) {
            await Future<void>.delayed(
              Duration(milliseconds: description.pingIntervalMs),
            );
          }
        }
      }
      if (ack == null) {
        throw TimeoutException(
          'Ping ${description.pingAttempts} 次均未收到应答',
          Duration(milliseconds: description.pingTimeoutMs),
        );
      }
      ping.decodeAck(ack.data);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _buildDevicePage(description)),
      );
    } catch (error) {
      await _ble.disconnect();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('连接或 Ping 验证失败：$error')));
      }
    } finally {
      if (mounted) {
        setState(() => _connectingDeviceId = null);
        if (!FlutterBluePlus.isScanningNow) {
          unawaited(_scanForConfiguredDevices());
        }
      }
    }
  }

  Widget _buildDevicePage(DeviceDescription description) {
    return switch (description.page) {
      'ega' => const EgaDevicePage(),
      _ => const DevicePage(),
    };
  }

  @override
  void dispose() {
    _cornerTapTimer?.cancel();
    _presenceTimer?.cancel();
    _scanResultsSubscription?.cancel();
    _scanningSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('首页')),
    body: Stack(
      children: [
        Positioned.fill(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                Theme.of(context).scaffoldBackgroundColor
                    .withValues(alpha: 0.68),
                BlendMode.srcOver,
              ),
              child: Image.asset(
                'assets/images/gnu/gnu-head.png',
                fit: BoxFit.cover,
                alignment: Alignment.center,
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('欢迎使用', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 24),
                if (_matchingDevices.isNotEmpty)
                  ..._matchingDevices.map(_buildDeviceCard)
                else
                  _buildScanStatus(),
              ],
            ),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleCornerTap,
            child: const SizedBox(width: 64, height: 64),
          ),
        ),
      ],
    ),
  );
}
