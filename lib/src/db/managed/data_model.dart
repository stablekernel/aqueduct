import 'dart:mirrors';
import 'managed.dart';
import 'data_model_builder.dart';

/// Instances of this class contain descriptions and metadata for mapping [ManagedObject]s to database rows.
///
/// A data model describes each database table to [ManagedObject] object mapping for a single database. For each
/// mapping, there is an instance of [ManagedEntity] - a data model is a collection of such entities.
///
/// Data models are created by reflecting on an Aqueduct application library or by providing a list of
/// types that extend [ManagedObject].
class ManagedDataModel {
  /// Creates an instance of [ManagedDataModel] from a list of types that extend [ManagedObject]. It is preferable
  /// to use [ManagedDataModel.fromCurrentMirrorSystem] over this method.
  ///
  /// To register a class as a managed object within this data model, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  ManagedDataModel(List<Type> instanceTypes) {
    var builder = new DataModelBuilder(this, instanceTypes);
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
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
    var managedObjectMirror = reflectClass(ManagedObject);
    var classes = currentMirrorSystem()
        .libraries
        .values
        .where((lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file")
        .expand((lib) => lib.declarations.values)
        .where((decl) => decl is ClassMirror && decl.isSubclassOf(managedObjectMirror) && decl != managedObjectMirror)
        .map((decl) => decl as ClassMirror)
        .toList();

    var builder = new DataModelBuilder(this, classes.map((cm) => cm.reflectedType).toList());
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance on [ManagedDataModel] from all of the declared [ManagedObject] subclasses declared in the same package as [type].
  ///
  /// This method now simply calls [ManagedDataModel.fromCurrentMirrorSystem].
  @deprecated
  factory ManagedDataModel.fromPackageContainingType(Type type) {
    return new ManagedDataModel.fromCurrentMirrorSystem();
  }

  /// Creates an instance of a [ManagedDataModel] from a package on the filesystem.
  ///
  /// This method now simply calls [ManagedDataModel.fromCurrentMirrorSystem].
  @deprecated
  factory ManagedDataModel.fromURI(Uri libraryURI) {
    return new ManagedDataModel.fromCurrentMirrorSystem();
  }

  Iterable<ManagedEntity> get entities => _entities.values;
  Map<Type, ManagedEntity> _entities = {};
  Map<Type, ManagedEntity> _persistentTypeToEntityMap = {};

  /// Returns a [ManagedEntity] for a [Type].
  ///
  /// [type] may be either a subclass of [ManagedObject] or a [ManagedObject]'s persistent type. For example, the following
  /// definition, you could retrieve its entity by passing MyModel or _MyModel as an argument to this method:
  ///
  ///         class MyModel extends ManagedObject<_MyModel> implements _MyModel {}
  ///         class _MyModel {
  ///           @primaryKey
  ///           int id;
  ///         }
  ManagedEntity entityForType(Type type) {
    return _entities[type] ?? _persistentTypeToEntityMap[type];
  }
}

/// Thrown when a [ManagedDataModel] encounters an error.
class ManagedDataModelException implements Exception {
  ManagedDataModelException(this.message);

  final String message;

  String toString() {
    return "DataModelException: $message";
  }
}
