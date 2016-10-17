part of aqueduct;

/// Instances of this class contain descriptions and metadata for mapping model objects to database rows.
///
/// A data model describes each database table to model object mapping for a single database. For each
/// mapping, there is an instance of [ModelEntity] - a data model is a collection of such entities.
///
/// Data models are created by reflecting on an Aqueduct application library or by providing a list of
/// types that extend [Model].
class DataModel {
  /// Creates an instance of [DataModel] from a list of types that extend [Model]. It is preferable
  /// to use [DataModel.fromPackageContainingType] over this method.
  ///
  /// To register a class as a model object within this data model, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  DataModel(List<Type> instanceTypes) {
    var builder = new _DataModelBuilder(this, instanceTypes);
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance on [DataModel] from all of the declared [Model] subclasses declared in the same package as [type].
  ///
  /// This is a convenience constructor for creating a [DataModel] from an application package. It will find all subclasses of `Model`
  /// in the package that [type] belongs to. Typically, you pass the [Type] of an application's [RequestSink] subclass.
  DataModel.fromPackageContainingType(Type type) {
    LibraryMirror libMirror = reflectType(type).owner;

    var builder = new _DataModelBuilder(this, _modelTypesFromLibraryMirror(libMirror));
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance of a [DataModel] from a package on the filesystem.
  ///
  /// This method is used by database migration tools.
  DataModel.fromURI(Uri libraryURI) {
    if (!libraryURI.isAbsolute) {
      libraryURI = new Uri.file(libraryURI.path);
    }
    var libMirror = currentMirrorSystem().libraries[libraryURI];
    var builder = new _DataModelBuilder(this, _modelTypesFromLibraryMirror(libMirror));
    _entities = builder.entities;
  }

  Map<Type, ModelEntity> _entities = {};
  Map<Type, ModelEntity> _persistentTypeToEntityMap = {};

  /// Returns a [ModelEntity] for a [Type].
  ///
  /// [type] may be either the instance type or persistent type. For example, the following model
  /// definition, you could retrieve its entity by passing MyModel or _MyModel as an argument to this method:
  ///
  ///         class MyModel extends Model<_MyModel> implements _MyModel {}
  ///         class _MyModel {
  ///           @primaryKey
  ///           int id;
  ///         }
  ModelEntity entityForType(Type type) {
    return _entities[type] ?? _persistentTypeToEntityMap[type];
  }

  List<Type> _modelTypesFromLibraryMirror(LibraryMirror libMirror) {
    var modelMirror = reflectClass(Model);
    Iterable<ClassMirror> allClasses = libMirror.declarations.values
        .where((decl) => decl is ClassMirror)
        .map((decl) => decl as ClassMirror);

    return allClasses
        .where((m) => m.isSubclassOf(modelMirror))
        .map((m) => m.reflectedType)
        .toList();
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