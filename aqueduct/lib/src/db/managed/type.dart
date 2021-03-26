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
  /// [mirror] must be representable by [ManagedPropertyType].
  ManagedType(this.mirror) {
    if (mirror.isAssignableTo(reflectType(int))) {
      kind = ManagedPropertyType.integer;
    } else if (mirror.isAssignableTo(reflectType(String))) {
      kind = ManagedPropertyType.string;
    } else if (mirror.isAssignableTo(reflectType(DateTime))) {
      kind = ManagedPropertyType.datetime;
    } else if (mirror.isAssignableTo(reflectType(bool))) {
      kind = ManagedPropertyType.boolean;
    } else if (mirror.isAssignableTo(reflectType(double))) {
      kind = ManagedPropertyType.doublePrecision;
    } else if (mirror.isSubtypeOf(reflectType(Map))) {
      if (!mirror.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw UnsupportedError(
            "Invalid type '${mirror.reflectedType}' for 'ManagedType'. Key is invalid; must be 'String'.");
      }
      kind = ManagedPropertyType.map;
      elements = ManagedType(mirror.typeArguments.last);
    } else if (mirror.isSubtypeOf(reflectType(List))) {
      kind = ManagedPropertyType.list;
      elements = ManagedType(mirror.typeArguments.first);
    } else if (mirror.isAssignableTo(reflectType(Document))) {
      kind = ManagedPropertyType.document;
    } else if (mirror is ClassMirror && (mirror as ClassMirror).isEnum) {
      kind = ManagedPropertyType.string;
      final enumeratedCases = (mirror as ClassMirror).getField(#values).reflectee as List<dynamic>;
      enumerationMap =
        enumeratedCases.fold(<String, dynamic>{}, (m, v) {
          m[v.toString().split(".").last] = v;
          return m;
        });
    } else {
      throw UnsupportedError(
          "Invalid type '${mirror.reflectedType}' for 'ManagedType'.");
    }
  }

  /// Creates a new instance from a [ManagedPropertyType];
  ManagedType.fromKind(this.kind) {
    switch (kind) {
      case ManagedPropertyType.bigInteger:
        {
          mirror = reflectClass(int);
        }
        break;
      case ManagedPropertyType.boolean:
        {
          mirror = reflectClass(bool);
        }
        break;
      case ManagedPropertyType.datetime:
        {
          mirror = reflectClass(DateTime);
        }
        break;
      case ManagedPropertyType.document:
        {
          mirror = reflectClass(Document);
        }
        break;
      case ManagedPropertyType.doublePrecision:
        {
          mirror = reflectClass(double);
        }
        break;
      case ManagedPropertyType.integer:
        {
          mirror = reflectClass(int);
        }
        break;
      case ManagedPropertyType.string:
        {
          mirror = reflectClass(String);
        }
        break;
      case ManagedPropertyType.list:
      case ManagedPropertyType.map:
        {
          throw ArgumentError(
              "Cannot instantiate 'ManagedType' from type 'list' or 'map'. Use default constructor.");
        }
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

  /// Dart representation of this type.
  TypeMirror mirror;

  /// Whether this is an enum type.
  bool get isEnumerated => enumerationMap != null;

  /// For enumerated types, this is a map of the name of the option to its Dart enum type.
  Map<String, dynamic> enumerationMap;

  /// Whether [dartValue] can be assigned to properties with this type.
  bool isAssignableWith(dynamic dartValue) {
    if (dartValue == null) {
      return true;
    }

    return reflect(dartValue).type.isAssignableTo(mirror);
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
