part of aqueduct;

/// Instances of this class contain descriptions and metadata for mapping [ManagedObject]s to database rows.
///
/// A data model describes each database table to [ManagedObject] object mapping for a single database. For each
/// mapping, there is an instance of [ManagedEntity] - a data model is a collection of such entities.
///
/// Data models are created by reflecting on an Aqueduct application library or by providing a list of
/// types that extend [ManagedObject].
class ManagedDataModel {
  /// Creates an instance of [ManagedDataModel] from a list of types that extend [ManagedObject]. It is preferable
  /// to use [ManagedDataModel.fromPackageContainingType] over this method.
  ///
  /// To register a class as a managed object within this data model, you must include its type in the list. Example:
  ///
  ///       new DataModel([User, Token, Post]);
  ManagedDataModel(List<Type> instanceTypes) {
    var builder = new _DataModelBuilder(this, instanceTypes);
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance on [ManagedDataModel] from all of the declared [ManagedObject] subclasses declared in the same package as [type].
  ///
  /// This is a convenience constructor for creating a [ManagedDataModel] from an application package. It will find all subclasses of [ManagedObject]
  /// in the package that [type] belongs to. Typically, you pass the [Type] of an application's [RequestSink] subclass.
  ManagedDataModel.fromPackageContainingType(Type type) {
    LibraryMirror libMirror = reflectType(type).owner;

    var builder = new _DataModelBuilder(this, _modelTypesFromLibraryMirror(libMirror));
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
  }

  /// Creates an instance of a [ManagedDataModel] from a package on the filesystem.
  ///
  /// This method is used by database migration tools.
  ManagedDataModel.fromURI(Uri libraryURI) {
    if (!libraryURI.isAbsolute) {
      libraryURI = new Uri.file(libraryURI.path);
    }
    var libMirror = currentMirrorSystem().libraries[libraryURI];
    var builder = new _DataModelBuilder(this, _modelTypesFromLibraryMirror(libMirror));
    _entities = builder.entities;
  }

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

  List<Type> _modelTypesFromLibraryMirror(LibraryMirror libMirror) {
    var modelMirror = reflectClass(ManagedObject);
    Iterable<ClassMirror> allClasses = libMirror.declarations.values
        .where((decl) => decl is ClassMirror)
        .map((decl) => decl as ClassMirror);

    return allClasses
        .where((m) => m.isSubclassOf(modelMirror))
        .map((m) => m.reflectedType)
        .toList();
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