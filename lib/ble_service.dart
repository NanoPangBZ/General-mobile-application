import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// BLE central service. Select a writable and notifiable characteristic after
/// connecting, then attach it to com_host as a byte transport.
class BleService {
  BleService._();

  static final BleService instance = BleService._();

  final Map<String, ScanResult> _scanResults = {};
  final StreamController<List<ScanResult>> _results =
      StreamController<List<ScanResult>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notifySubscription;

  Stream<List<ScanResult>> get scanResults => _results.stream;
  BluetoothDevice? get connectedDevice => _device;
  bool get isConnected => _device != null;

  Stream<Uint8List> get incomingBytes {
    final characteristic = _rx;
    if (characteristic == null) {
      throw StateError('Select a notify characteristic before reading');
    }
    return characteristic.onValueReceived.map(Uint8List.fromList);
  }

  Future<bool> get isSupported => FlutterBluePlus.isSupported;

  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    List<Guid> withServices = const [],
  }) async {
    _scanResults.clear();
    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        _scanResults[result.device.remoteId.str] = result;
      }
      _results.add(List.unmodifiable(_scanResults.values));
    }, onError: _results.addError);
    FlutterBluePlus.cancelWhenScanComplete(_scanSubscription!);
    await FlutterBluePlus.startScan(timeout: timeout, withServices: withServices);
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  Future<List<BluetoothService>> connect(BluetoothDevice device) async {
    if (_device != null && _device!.remoteId != device.remoteId) {
      await disconnect();
    }
    if (device.isDisconnected) await device.connect(license: License.nonprofit);
    _device = device;
    return device.discoverServices();
  }

  /// Configure the GATT characteristics used for byte stream RX and TX.
  Future<void> configureTransport({
    required BluetoothCharacteristic receive,
    required BluetoothCharacteristic transmit,
  }) async {
    if (_device == null) throw StateError('Connect to a device first');
    if (!receive.properties.notify && !receive.properties.indicate) {
      throw ArgumentError('Receive characteristic must support notify/indicate');
    }
    if (!transmit.properties.write && !transmit.properties.writeWithoutResponse) {
      throw ArgumentError('Transmit characteristic must support write');
    }
    await _notifySubscription?.cancel();
    _rx = receive;
    _tx = transmit;
    await receive.setNotifyValue(true);
  }

  Future<void> write(Uint8List bytes) async {
    final characteristic = _tx;
    if (characteristic == null) throw StateError('Transport is not configured');
    final withoutResponse = characteristic.properties.writeWithoutResponse &&
        !characteristic.properties.write;
    final maxChunk = (await _device!.mtu.first) - 3;
    for (var offset = 0; offset < bytes.length; offset += maxChunk) {
      final end = (offset + maxChunk < bytes.length) ? offset + maxChunk : bytes.length;
      await characteristic.write(bytes.sublist(offset, end),
          withoutResponse: withoutResponse, allowLongWrite: !withoutResponse);
    }
  }

  Future<void> disconnect() async {
    await _notifySubscription?.cancel();
    _notifySubscription = null;
    _rx = null;
    _tx = null;
    final device = _device;
    _device = null;
    if (device != null && device.isConnected) await device.disconnect();
  }

  Future<void> dispose() async {
    await stopScan();
    await _scanSubscription?.cancel();
    await disconnect();
    await _results.close();
  }
}
