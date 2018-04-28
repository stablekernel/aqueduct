import 'dart:mirrors';
import 'package:aqueduct/src/db/managed/document.dart';

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
  list,

  /// Represented by instances of [Document]
  document
}

/// Complex type storage for [ManagedEntity] attributes.
class ManagedType {
  /// Creates a new instance from a [ClassMirror].
  ///
  /// [t] must be representable by [ManagedPropertyType].
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
      if (!t.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw new UnsupportedError("Invalid type '$t' for 'ManagedType'. Key is invalid; must be 'String'.");
      }
      kind = ManagedPropertyType.map;
      elements = new ManagedType(t.typeArguments.last);
    } else if (t.isSubtypeOf(reflectType(List))) {
      kind = ManagedPropertyType.list;
      elements = new ManagedType(t.typeArguments.first);
    } else if (t.isAssignableTo(reflectType(Document))) {
      kind = ManagedPropertyType.document;
    } else if (t.isEnum) {
      kind = ManagedPropertyType.string;
    } else {
      throw new UnsupportedError("Invalid type '$t' for 'ManagedType'.");
    }
  }

  /// Creates a new instance from a [ManagedPropertyType];
  ManagedType.fromKind(this.kind) {
    if (kind == ManagedPropertyType.list || kind == ManagedPropertyType.map) {
      throw new ArgumentError("Cannot instantiate 'ManagedType' from complex type 'list' or 'map'. Use default constructor.");
    }
  }

  /// The primitive kind of this type.
  ///
  /// All types have a kind. If kind is a map or list, it will also have [elements].
  ManagedPropertyType kind;

  /// The primitive kind of each element of this type.
  ///
  /// If [kind] is a collection (map or list), this value stores the type of each element in the collection.
  /// Keys of map types are always [String].
  ManagedType elements;

  /// Whether [dartValue] can be assigned to properties with this type.
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
      case ManagedPropertyType.document:
        return dartValue is Document;
    }
    return false;
  }


  @override
  String toString() {
    return "$kind";
  }

  static List<Type> get supportedDartTypes {
    return [String, DateTime, bool, int, double, Document];
  }

  static ManagedPropertyType get integer => ManagedPropertyType.integer;

  static ManagedPropertyType get bigInteger => ManagedPropertyType.bigInteger;

  static ManagedPropertyType get string => ManagedPropertyType.string;

  static ManagedPropertyType get datetime => ManagedPropertyType.datetime;

  static ManagedPropertyType get boolean => ManagedPropertyType.boolean;

  static ManagedPropertyType get doublePrecision => ManagedPropertyType.doublePrecision;

  static ManagedPropertyType get map => ManagedPropertyType.map;

  static ManagedPropertyType get list => ManagedPropertyType.list;

  static ManagedPropertyType get document => ManagedPropertyType.document;
}
