import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Runtime view of the generated native protocol catalogue.
class ProtocolMessageCatalog {
  ProtocolMessageCatalog._(this._messages);

  static const assetPath =
      'native/com_host/protocol/flutter_msg_data_def/messages.json';

  final List<Map<String, dynamic>> _messages;

  static Future<ProtocolMessageCatalog> load() async {
    final jsonText = await rootBundle.loadString(assetPath);
    final document = jsonDecode(jsonText) as Map<String, dynamic>;
    final rows = document['messages'] as List<dynamic>;
    return ProtocolMessageCatalog._(
      rows.cast<Map<String, dynamic>>(),
    );
  }

  MessageDefinition byName(String name) {
    final matches = _messages.where((message) => message['name'] == name);
    if (matches.isEmpty) throw StateError('Unknown protocol message: $name');
    return MessageDefinition._(matches.single);
  }
}

class MessageDefinition {
  const MessageDefinition._(this._json);

  final Map<String, dynamic> _json;

  int get id => _json['id'] as int;
  String get name => _json['name'] as String;
  String get brief => _json['brief'] as String;

  /// Encode the message payload from the generated field description.
  /// Empty/opaque structures (such as ping request data) have a zero-byte body.
  Uint8List encodeData([Map<String, Object?> values = const {}]) {
    final definition = _json['data'] as Map<String, dynamic>?;
    if (definition == null || definition['kind'] == 'opaque') {
      if (values.isNotEmpty) {
        throw ArgumentError('$name has no described payload fields');
      }
      return Uint8List(0);
    }
    final fields = definition['fields'] as List<dynamic>? ?? const [];
    final writer = _PayloadWriter();
    for (final item in fields) {
      final field = item as Map<String, dynamic>;
      final fieldName = field['name'] as String;
      if (field.containsKey('bitWidth')) {
        throw UnsupportedError('Encoding bitfield $fieldName is not implemented');
      }
      final value = values[fieldName];
      if (value == null) throw ArgumentError('Missing value for $fieldName');
      writer.write(field['type'] as String, value, field['length'] as int?);
    }
    return writer.bytes;
  }

  Map<String, Object?> decodeAck(Uint8List bytes) {
    final definition = _json['ack'] as Map<String, dynamic>?;
    if (definition == null || definition['kind'] == 'opaque') return {'raw': bytes};
    final fields = definition['fields'] as List<dynamic>? ?? const [];
    final data = ByteData.sublistView(bytes);
    var offset = 0;
    final result = <String, Object?>{};
    for (final item in fields) {
      final field = item as Map<String, dynamic>;
      final name = field['name'] as String;
      if (field.containsKey('bitWidth')) {
        throw UnsupportedError('Decoding bitfield $name is not implemented');
      }
      final type = field['type'] as String;
      final length = field['length'] as int? ?? 1;
      final size = _PayloadWriter.sizeOf(type);
      if (size == null) throw UnsupportedError('Unsupported ACK field type: $type');
      if (offset + size * length > bytes.length) {
        throw FormatException('ACK too short while reading $name');
      }
      final values = <Object>[];
      for (var i = 0; i < length; i++) {
        values.add(_readScalar(data, offset, type));
        offset += size;
      }
      result[name] = field.containsKey('length') ? values : values.single;
    }
    if (offset != bytes.length) result['_trailingBytes'] = bytes.length - offset;
    return result;
  }

  Object _readScalar(ByteData data, int offset, String type) => switch (type) {
        'uint8_t' => data.getUint8(offset),
        'int8_t' => data.getInt8(offset),
        'uint16_t' => data.getUint16(offset, Endian.little),
        'int16_t' => data.getInt16(offset, Endian.little),
        'uint32_t' => data.getUint32(offset, Endian.little),
        'int32_t' => data.getInt32(offset, Endian.little),
        'uint64_t' => data.getUint64(offset, Endian.little),
        'int64_t' => data.getInt64(offset, Endian.little),
        'float' => data.getFloat32(offset, Endian.little),
        'double' => data.getFloat64(offset, Endian.little),
        _ => throw UnsupportedError('Unsupported ACK field type: $type'),
      };
}

class _PayloadWriter {
  final _builder = BytesBuilder(copy: false);
  Uint8List get bytes => _builder.takeBytes();

  static int? sizeOf(String type) => switch (type) {
        'uint8_t' || 'int8_t' || 'char' => 1,
        'uint16_t' || 'int16_t' => 2,
        'uint32_t' || 'int32_t' || 'float' => 4,
        'uint64_t' || 'int64_t' || 'double' => 8,
        _ => null,
      };

  void write(String type, Object value, int? arrayLength) {
    final count = arrayLength ?? 1;
    final values = arrayLength == null ? [value] : value as List<Object?>;
    if (values.length != count) {
      throw ArgumentError('Expected $count values for $type array');
    }
    final size = sizeOf(type);
    if (size == null) throw UnsupportedError('Unsupported payload field type: $type');
    final data = ByteData(size * count);
    for (var i = 0; i < count; i++) {
      final number = values[i] as num;
      final offset = i * size;
      switch (type) {
        case 'uint8_t':
        case 'char':
          data.setUint8(offset, number.toInt());
          break;
        case 'int8_t':
          data.setInt8(offset, number.toInt());
          break;
        case 'uint16_t':
          data.setUint16(offset, number.toInt(), Endian.little);
          break;
        case 'int16_t':
          data.setInt16(offset, number.toInt(), Endian.little);
          break;
        case 'uint32_t':
          data.setUint32(offset, number.toInt(), Endian.little);
          break;
        case 'int32_t':
          data.setInt32(offset, number.toInt(), Endian.little);
          break;
        case 'uint64_t':
          data.setUint64(offset, number.toInt(), Endian.little);
          break;
        case 'int64_t':
          data.setInt64(offset, number.toInt(), Endian.little);
          break;
        case 'float':
          data.setFloat32(offset, number.toDouble(), Endian.little);
          break;
        case 'double':
          data.setFloat64(offset, number.toDouble(), Endian.little);
          break;
      }
    }
    _builder.add(data.buffer.asUint8List());
  }
}
