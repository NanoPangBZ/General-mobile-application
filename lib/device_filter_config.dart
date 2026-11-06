import 'dart:convert';

/// Device matching configuration embedded in the application bundle.
const String deviceFilterJson = r'''
{
  "devices": [
    {
      "productName": "电吉他音箱",
      "bleName": {
        "pattern": "EGA",
        "match": "exact"
      },
      "sppble": {
        "serviceUuid": null,
        "writeCharacteristicUuid": null,
        "notifyCharacteristicUuid": "0000ff99-0000-1000-8000-00805f9b34fb",
        "enableNotifications": true,
        "cccdDescriptorUuid": "00002902-0000-1000-8000-00805f9b34fb"
      }
    }
  ]
}
''';

class DeviceFilterConfig {
  const DeviceFilterConfig({required this.devices});

  final List<ConfiguredDevice> devices;

  static DeviceFilterConfig fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return DeviceFilterConfig(
      devices: (json['devices'] as List<dynamic>)
          .map(
            (item) => ConfiguredDevice.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class ConfiguredDevice {
  const ConfiguredDevice({
    required this.productName,
    required this.bleNamePattern,
    required this.bleNameMatch,
    required this.sppble,
  });

  final String productName;
  final String bleNamePattern;
  final String bleNameMatch;
  final Map<String, dynamic> sppble;

  factory ConfiguredDevice.fromJson(Map<String, dynamic> json) {
    final bleName = json['bleName'] as Map<String, dynamic>;
    return ConfiguredDevice(
      productName: json['productName'] as String,
      bleNamePattern: bleName['pattern'] as String,
      bleNameMatch: bleName['match'] as String,
      sppble: Map<String, dynamic>.unmodifiable(
        json['sppble'] as Map<String, dynamic>,
      ),
    );
  }

  bool matches(String name) {
    if (bleNameMatch == 'exact') return name == bleNamePattern;
    if (bleNameMatch == 'wildcard') {
      final escaped = RegExp.escape(bleNamePattern)
          .replaceAll(r'\*', '.*')
          .replaceAll(r'\?', '.');
      final regex = RegExp('^$escaped\$');
      return regex.hasMatch(name);
    }
    return false;
  }
}

final DeviceFilterConfig deviceFilterConfig = DeviceFilterConfig.fromJson(
  deviceFilterJson,
);
