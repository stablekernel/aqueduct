import 'dart:mirrors';
import 'managed.dart';

/// Possible data types for [ManagedEntity] attributes.
enum ManagedPropertyType {
  /// Represented by instances of [int].
  integer,

  /// Represented by instances of [int].
  bigInteger,

  /// Represented by instances of [String].
  string,

  /// Represented by instances of [DateTime].
  datetime,

  /// Represented by instances of [bool].
  boolean,

  /// Represented by instances of [double].
  doublePrecision,

  /// Represented by instances of [Map].
  map,

  /// Represented by instances of [List].
  list
}

class ManagedType {
  ManagedType(ClassMirror t) {
    if (t.isAssignableTo(reflectType(int))) {
      kind = ManagedPropertyType.integer;
    } else if (t.isAssignableTo(reflectType(String))) {
      kind = ManagedPropertyType.string;
    } else if (t.isAssignableTo(reflectType(DateTime))) {
      kind = ManagedPropertyType.datetime;
    } else if (t.isAssignableTo(reflectType(bool))) {
      kind = ManagedPropertyType.boolean;
    } else if (t.isAssignableTo(reflectType(double))) {
      kind = ManagedPropertyType.doublePrecision;
    } else if (t.isSubtypeOf(reflectType(Map))) {
      kind = ManagedPropertyType.map;
      elements = new ManagedType(t.typeArguments.last);
    } else if (t.isSubtypeOf(reflectType(List))) {
      kind = ManagedPropertyType.list;
      elements = new ManagedType(t.typeArguments.first);
    } else if (t.isEnum) {
      kind = ManagedPropertyType.string;
    } else {
      throw new UnsupportedError("Invalid type '$t' for 'ManagedType'.");
    }
  }

  ManagedType.fromKind(this.kind);

  ManagedPropertyType kind;
  ManagedType elements;

  bool isAssignableWith(dynamic dartValue) {
    if (dartValue == null) {
      return true;
    }

    switch (kind) {
      case ManagedPropertyType.integer:
        return dartValue is int;
      case ManagedPropertyType.bigInteger:
        return dartValue is int;
      case ManagedPropertyType.boolean:
        return dartValue is bool;
      case ManagedPropertyType.datetime:
        return dartValue is DateTime;
      case ManagedPropertyType.doublePrecision:
        return dartValue is double;
      case ManagedPropertyType.string:
        return dartValue is String;
      case ManagedPropertyType.map:
        return dartValue is Map;
      case ManagedPropertyType.list:
        return dartValue is List;
    }
    return false;
  }


  @override
  String toString() {
    return "$kind";
  }

  static List<Type> get supportedDartTypes {
    return [String, DateTime, bool, int, double];
  }

  static ManagedPropertyType get integer => ManagedPropertyType.integer;

  static ManagedPropertyType get bigInteger => ManagedPropertyType.bigInteger;

  static ManagedPropertyType get string => ManagedPropertyType.string;

  static ManagedPropertyType get datetime => ManagedPropertyType.datetime;

  static ManagedPropertyType get boolean => ManagedPropertyType.boolean;

  static ManagedPropertyType get doublePrecision => ManagedPropertyType.doublePrecision;

  static ManagedPropertyType get map => ManagedPropertyType.map;

  static ManagedPropertyType get list => ManagedPropertyType.list;
}
