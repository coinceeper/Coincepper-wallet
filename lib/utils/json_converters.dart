import 'package:json_annotation/json_annotation.dart';

/// Custom converter for boolean values that might come as integers (0/1) from API
class BoolIntConverter implements JsonConverter<bool, dynamic> {
  const BoolIntConverter();

  @override
  bool fromJson(dynamic json) {
    if (json is bool) {
      return json;
    } else if (json is int) {
      return json != 0;
    } else if (json is String) {
      return json.toLowerCase() == 'true' || json == '1';
    }
    return false; // Default fallback
  }

  @override
  dynamic toJson(bool object) => object;
}

/// Custom converter for nullable boolean values that might come as integers (0/1) from API
class NullableBoolIntConverter implements JsonConverter<bool?, dynamic> {
  const NullableBoolIntConverter();

  @override
  bool? fromJson(dynamic json) {
    if (json == null) return null;
    if (json is bool) {
      return json;
    } else if (json is int) {
      return json != 0;
    } else if (json is String) {
      return json.toLowerCase() == 'true' || json == '1';
    }
    return false; // Default fallback
  }

  @override
  dynamic toJson(bool? object) => object;
}
