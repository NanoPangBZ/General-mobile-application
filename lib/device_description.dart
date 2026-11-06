import 'dart:convert';

/// Device matching configuration embedded in the application bundle.
const String deviceDescriptionJson = r'''
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

class DeviceDescriptionCatalog {
  const DeviceDescriptionCatalog({required this.devices});

  final List<DeviceDescription> devices;

  static DeviceDescriptionCatalog fromJson(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    return DeviceDescriptionCatalog(
      devices: (json['devices'] as List<dynamic>)
          .map(
            (item) => DeviceDescription.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class DeviceDescription {
  const DeviceDescription({
    required this.productName,
    required this.bleNamePattern,
    required this.bleNameMatch,
    required this.sppble,
  });

  final String productName;
  final String bleNamePattern;
  final String bleNameMatch;
  final Map<String, dynamic> sppble;

  factory DeviceDescription.fromJson(Map<String, dynamic> json) {
    final bleName = json['bleName'] as Map<String, dynamic>;
    return DeviceDescription(
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

final DeviceDescriptionCatalog deviceDescriptions = DeviceDescriptionCatalog.fromJson(
  deviceDescriptionJson,
);
