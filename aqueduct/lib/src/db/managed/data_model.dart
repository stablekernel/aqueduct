import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/utilities/reference_counting_list.dart';

import 'package:aqueduct/src/db/query/query.dart';

import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:runtime/runtime.dart';

/// Instances of this class contain descriptions and metadata for mapping [ManagedObject]s to database rows.
///
/// An instance of this type must be used to initialize a [ManagedContext], and so are required to use [Query]s.
///
/// The [ManagedDataModel.fromCurrentMirrorSystem] constructor will reflect on an application's code and find
/// all subclasses of [ManagedObject], building a [ManagedEntity] for each.
///
/// Most applications do not need to access instances of this type.
///
class ManagedDataModel extends Object
    with ReferenceCountable
    implements APIComponentDocumenter {
  /// Creates an instance of [ManagedDataModel] from a list of types that extend [ManagedObject]. It is preferable
  /// to use [ManagedDataModel.fromCurrentMirrorSystem] over this method.
  ///
  /// To register a class as a managed object within this data model, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  ManagedDataModel(List<Type> instanceTypes) {
    final runtimes = RuntimeContext.current.runtimes.iterable
        .whereType<ManagedEntityRuntime>()
        .toList();
    final expectedRuntimes = instanceTypes
        .map((t) => runtimes.firstWhere((e) => e.entity.instanceType == t,
            orElse: () => null))
        .toList();

    final notFound = expectedRuntimes.where((e) => e == null).toList();
    if (notFound.isNotEmpty) {
      throw ManagedDataModelError(
          "Data model types were not found: ${notFound.map((e) => e.entity.name).join(", ")}");
    }

    expectedRuntimes.forEach((runtime) {
      _entities[runtime.entity.instanceType] = runtime.entity;
      _tableDefinitionToEntityMap[runtime.entity.tableDefinition] =
          runtime.entity;
    });
    expectedRuntimes.forEach((runtime) => runtime.finalize(this));
  }

  /// Creates an instance of a [ManagedDataModel] from all subclasses of [ManagedObject] in all libraries visible to the calling library.
  ///
  /// This constructor will search every available package and file library that is visible to the library
  /// that runs this constructor for subclasses of [ManagedObject]. A [ManagedEntity] will be created
  /// and stored in this instance for every such class found.
  ///
  /// Standard Dart libraries (prefixed with 'dart:') and URL-encoded libraries (prefixed with 'data:') are not searched.
  ///
  /// This is the preferred method of instantiating this type.
  ManagedDataModel.fromCurrentMirrorSystem() {
    final runtimes = RuntimeContext.current.runtimes.iterable
        .whereType<ManagedEntityRuntime>();

    runtimes.forEach((runtime) {
      _entities[runtime.entity.instanceType] = runtime.entity;
      _tableDefinitionToEntityMap[runtime.entity.tableDefinition] =
          runtime.entity;
    });
    runtimes.forEach((runtime) => runtime.finalize(this));
  }

  Iterable<ManagedEntity> get entities => _entities.values;
  Map<Type, ManagedEntity> _entities = {};
  Map<String, ManagedEntity> _tableDefinitionToEntityMap = {};

  /// Returns a [ManagedEntity] for a [Type].
  ///
  /// [type] may be either a subclass of [ManagedObject] or a [ManagedObject]'s table definition. For example, the following
  /// definition, you could retrieve its entity by passing MyModel or _MyModel as an argument to this method:
  ///
  ///         class MyModel extends ManagedObject<_MyModel> implements _MyModel {}
  ///         class _MyModel {
  ///           @primaryKey
  ///           int id;
  ///         }
  ManagedEntity entityForType(Type type) {
    return _entities[type] ?? _tableDefinitionToEntityMap[type.toString()];
  }

  @override
  void documentComponents(APIDocumentContext context) {
    entities.forEach((e) => e.documentComponents(context));
  }
}

/// Thrown when a [ManagedDataModel] encounters an error.
class ManagedDataModelError extends Error {
  ManagedDataModelError(this.message);

  final String message;

  @override
  String toString() {
    return "Data Model Error: $message";
  }
}
