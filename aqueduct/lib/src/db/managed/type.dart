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
  /// Creates a new instance.
  ///
  /// [type] must be representable by [ManagedPropertyType].
  ManagedType(this.type, this.kind, this.elements, this.enumerationMap);

  // ignore: prefer_constructors_over_static_methods
  static ManagedType make<T>(ManagedPropertyType kind, ManagedType elements,
      Map<String, dynamic> enumerationMap) {
    return ManagedType(T, kind, elements, enumerationMap);
  }

  /// The primitive kind of this type.
  ///
  /// All types have a kind. If kind is a map or list, it will also have [elements].
  final ManagedPropertyType kind;

  /// The primitive kind of each element of this type.
  ///
  /// If [kind] is a collection (map or list), this value stores the type of each element in the collection.
  /// Keys of map types are always [String].
  final ManagedType elements;

  /// Dart representation of this type.
  final Type type;

  /// Whether this is an enum type.
  bool get isEnumerated => enumerationMap != null;

  /// For enumerated types, this is a map of the name of the option to its Dart enum type.
  final Map<String, dynamic> enumerationMap;

  /// Whether [dartValue] can be assigned to properties with this type.
  bool isAssignableWith(dynamic dartValue) {
    if (dartValue == null) {
      return true;
    }

    switch (kind) {
      case ManagedPropertyType.bigInteger:
        return dartValue is int;
      case ManagedPropertyType.integer:
        return dartValue is int;
      case ManagedPropertyType.boolean:
        return dartValue is bool;
      case ManagedPropertyType.datetime:
        return dartValue is DateTime;
      case ManagedPropertyType.doublePrecision:
        return dartValue is double;
      case ManagedPropertyType.map:
        return dartValue is Map<String, dynamic>;
      case ManagedPropertyType.list:
        return dartValue is List<dynamic>;
      case ManagedPropertyType.document:
        return dartValue is Document;
      case ManagedPropertyType.string:
        {
          if (enumerationMap != null) {
            return enumerationMap.values.contains(dartValue);
          }
          return dartValue is String;
        }
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

  static ManagedPropertyType get doublePrecision =>
      ManagedPropertyType.doublePrecision;

  static ManagedPropertyType get map => ManagedPropertyType.map;

  static ManagedPropertyType get list => ManagedPropertyType.list;

  static ManagedPropertyType get document => ManagedPropertyType.document;
}
