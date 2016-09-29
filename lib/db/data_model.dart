part of aqueduct;

/// Container for [ModelEntity]s, representing [Model] objects and their properties.
///
/// Required for [ModelContext].
class DataModel {
  /// Creates an instance of [DataModel] from a list of types that extends [Model].
  ///
  /// To register a class as a model object within this, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  DataModel(List<Type> instanceTypes) {
    var builder = new _DataModelBuilder(this, instanceTypes);
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance on [DataModel] from a list of [Model] instance types declared in the same package as [type].
  ///
  /// This is a convenience constructor for creating a [DataModel] for an application package. It will find all subclasses of `Model`
  /// in the package that [type] belongs to. Typically, you pass the [Type] of an application's [RequestSink] subclass.
  DataModel.fromPackageContainingType(Type type) {
    var modelMirror = reflectClass(Model);

    LibraryMirror libMirror = reflectType(type).owner;
    Iterable<ClassMirror> allClasses = libMirror.declarations.values
        .where((decl) => decl is ClassMirror);

    var modelTypes = allClasses
        .where((m) => m.isSubclassOf(modelMirror))
        .map((m) => m.reflectedType)
        .toList();

    var builder = new _DataModelBuilder(this, modelTypes);
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  DataModel._fromModelBundle(String modelBundlePath) {
    // This will build the model from a series of schema files.
  }

  Map<Type, ModelEntity> _entities = {};
  Map<Type, ModelEntity> _persistentTypeToEntityMap = {};

  /// Returns a [ModelEntity] for a [Type].
  ///
  /// [type] may be either the instance type or persistent type. For example, the following model
  /// definition, you could retrieve its entity via MyModel or _MyModel:
  ///
  ///         class MyModel extends Model<_MyModel> implements _MyModel {}
  ///         class _MyModel {
  ///           @primaryKey
  ///           int id;
  ///         }
  ModelEntity entityForType(Type type) {
    return _entities[type] ?? _persistentTypeToEntityMap[type];
  }
}

/// Thrown when a [DataModel] encounters an error.
class DataModelException implements Exception {
  DataModelException(this.message);

  final String message;

  String toString() {
    return "DataModelException: $message";
  }
}