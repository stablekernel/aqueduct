import 'dart:mirrors';
import 'managed.dart';
import 'data_model_builder.dart';

/// Instances of this class contain descriptions and metadata for mapping [ManagedObject]s to database rows.
///
/// An instance of this type must be used to initialize a [ManagedContext], and so are required to use [Query]s.
///
/// The [ManagedDataModel.fromCurrentMirrorSystem] constructor will reflect on an application's code and find
/// all subclasses of [ManagedObject], building a [ManagedEntity] for each.
///
/// Most applications do not need to access instances of this type.
///
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
        .where((decl) =>
            decl is ClassMirror &&
            decl.isSubclassOf(managedObjectMirror) &&
            decl != managedObjectMirror)
        .map((decl) => decl as ClassMirror)
        .toList();

    var builder = new DataModelBuilder(
        this, classes.map((cm) => cm.reflectedType).toList());
    _entities = builder.entities;
    _persistentTypeToEntityMap = builder.persistentTypeToEntityMap;
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

  factory ManagedDataModelException.noPrimaryKey(ManagedEntity entity) {
    return new ManagedDataModelException(
        "Class '${_getPersistentClassName(entity)}'"
        " doesn't declare a primary key property. All 'ManagedObject' subclasses "
        "must have a primary key. Usually, this means you want to add '@managedPrimaryKey int id;' "
        "to ${_getPersistentClassName(entity)}, but if you want more control over "
        "the type of primary key, declare the property as one of "
        "${ManagedPropertyDescription.supportedDartTypes.join(", ")} and "
        "add '@ManagedColumnAttribute(primaryKey: true)' above it.");
  }

  factory ManagedDataModelException.invalidType(
      ManagedEntity entity, Symbol property) {
    return new ManagedDataModelException("Property '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}'"
        " has an unsupported type. Must be "
        "${ManagedPropertyDescription.supportedDartTypes.join(", ")}"
        " or ManagedObject subclass (see also 'ManagedRelationship.deferred'). "
        "If you want to store something "
        "weird in the database, try declaring accessors in the ManagedObject subclass, "
        "and have those set values of the properties in the persistent type that are "
        "supported.");
  }

  factory ManagedDataModelException.invalidMetadata(
      ManagedEntity entity, Symbol property, ManagedEntity destinationEntity) {
    return new ManagedDataModelException(
        "Relationship '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}' "
        "cannot both have 'ManagedColumnAttributes' and 'ManagedRelationship' metadata. "
        "To add flags for indexing or nullability to a relationship, see the constructor "
        "for 'ManagedRelationship'.");
  }

  factory ManagedDataModelException.missingInverse(
      ManagedEntity entity,
      Symbol property,
      ManagedEntity destinationEntity,
      Symbol expectedProperty) {
    var expectedString = "Some property";
    if (expectedProperty != null) {
      expectedString = "'${_getName(expectedProperty)}'";
    }
    return new ManagedDataModelException(
        "Relationship '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}' has "
        "no inverse property. Every relationship must have an inverse. "
        "$expectedString on "
        "'${_getPersistentClassName(destinationEntity)}'"
        "is supposed to exist, and it should be either a "
        "'${_getInstanceClassName(entity)}' or"
        "'ManagedSet<${_getInstanceClassName(entity)} >'.");
  }

  factory ManagedDataModelException.incompatibleDeleteRule(
      ManagedEntity entity, Symbol property) {
    return new ManagedDataModelException(
        "Relationship '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}' "
        "has both 'RelationshipDeleteRule.nullify' and 'isRequired' equal to true, which "
        "couldn't possibly be true at the same. 'isRequired' means the column "
        "can't be null and 'nullify' means the column has to be null.");
  }

  factory ManagedDataModelException.dualMetadata(
      ManagedEntity entity,
      Symbol property,
      ManagedEntity destinationEntity,
      Symbol inverseProperty) {
    return new ManagedDataModelException("Relationship '${_getName(property)}' "
        "on '${_getPersistentClassName(entity)}' "
        "and '${_getName(inverseProperty)}' "
        "on '${_getPersistentClassName(destinationEntity)}' "
        "both have 'ManagedRelationship' metadata, but only one side can. "
        "The property with 'ManagedRelationship' metadata is actually a foreign key column "
        "in the database. The other one isn't a column, but an entire row or rows."
        "Ask yourself which makes more sense: "
        "\"${_getInstanceClassName(entity)}.${_getName(property)} has "
        "${_getInstanceClassName(destinationEntity)}.${_getName(inverseProperty)}\" "
        "or \"${_getInstanceClassName(destinationEntity)}.${_getName(inverseProperty)} has "
        "${_getInstanceClassName(entity)}.${_getName(property)}\"? If it is the first,"
        "keep the metadata on "
        "${_getInstanceClassName(destinationEntity)}.${_getName(inverseProperty)} "
        "otherwise, delete that metadata.");
  }

  factory ManagedDataModelException.duplicateInverse(
      ManagedEntity entity,
      Symbol property,
      ManagedEntity destinationEntity,
      List<Symbol> inversePropertyCandidates) {
    return new ManagedDataModelException("Relationship '${_getName(property)}' "
        "on '${_getPersistentClassName(entity)}' "
        "has more than one inverse property declared in "
        "${_getPersistentClassName(destinationEntity)}, but can only"
        "have one. The properties that claim to be an inverse "
        "are ${inversePropertyCandidates.map((s) => _getName(s)).join(",")}.");
  }

  factory ManagedDataModelException.noDestinationEntity(
      ManagedEntity entity, Symbol property) {
    var typeMirror = entity.persistentType.instanceMembers[property].returnType;
    return new ManagedDataModelException(
        "Relationship '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}' expects that there is a subclass "
        "of 'ManagedObject' named '${_getName(typeMirror.simpleName)}', "
        "but there isn't one. If you have declared one - and you really checked "
        "hard for typos - make sure that the class is visible to the script "
        "that starts the application or tests. (This usually means exporting "
        "that file from your application's main library file.");
  }

  factory ManagedDataModelException.multipleDestinationEntities(
      ManagedEntity entity,
      Symbol property,
      List<ManagedEntity> possibleEntities) {
    var destType =
        entity.persistentType.instanceMembers[property].returnType.simpleName;
    return new ManagedDataModelException(
        "Relationship '${_getName(property)}' on "
        "'${_getPersistentClassName(entity)}' expects that just one "
        "'ManagedObject' subclass uses a persistent type that extends "
        "'${_getName(destType)}. But the following implementations were found: "
        "${possibleEntities.map((e) => _getInstanceClassName(e))}. That's just "
        "how it is for now.");
  }

  factory ManagedDataModelException.invalidTransient(
      ManagedEntity entity, Symbol property) {
    return new ManagedDataModelException(
        "Transient property '${_getName(property)}' on "
        "'${_getInstanceClassName(entity)}' declares that"
        "it is transient, but it it has a mismatch. A transient "
        "getter method must have 'isAvailableAsOutput' and a transient "
        "setter method must have 'isAvailableAsInput'.");
  }

  factory ManagedDataModelException.duplicateTables(
      ManagedEntity entity1, ManagedEntity entity2) {
    return new ManagedDataModelException(
        "Entities '${_getInstanceClassName(entity1)}' and '${_getInstanceClassName(entity2)}' "
            "have the same table name: '${entity1.tableName}'. Rename these "
            "tables by changing the value in their 'tableName' method or removing "
            "the 'tableName' method altogether.");
  }

  factory ManagedDataModelException.cyclicReference(
      ManagedEntity entity,
      Symbol property,
      ManagedEntity destinationEntity,
      Symbol inverseProperty) {
    return new ManagedDataModelException(
        "Managed objects '${_getPersistentClassName(entity)}' "
        "and '${_getPersistentClassName(destinationEntity)}' "
        "have cyclic relationship properties. This would yield two tables "
        "with foreign key references to eachother. Try creating "
        "a 'ManagedObject' subclass that represents a join table between the two tables. "
        "The offending properties are: '${_getName(property)}' and '${_getName(inverseProperty)}'");
  }

  static String _getPersistentClassName(ManagedEntity entity) =>
      _getName(entity?.persistentType?.simpleName);

  static String _getInstanceClassName(ManagedEntity entity) =>
      _getName(entity?.instanceType?.simpleName);

  static String _getName(Symbol s) =>
      s != null ? MirrorSystem.getName(s) : null;

  final String message;

  String toString() {
    return "DataModelException: $message";
  }
}
