import 'dart:mirrors';

import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/utilities/reference_counting_list.dart';
import 'package:aqueduct/src/db/managed/builders/data_model_builder.dart';

import 'package:aqueduct/src/db/query/query.dart';

import 'package:aqueduct/src/db/managed/managed.dart';

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
    var builder = DataModelBuilder(this, instanceTypes);
    _entities = builder.entities;
    _tableDefinitionToEntityMap = builder.tableDefinitionToEntityMap;
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
    final builder =
        DataModelBuilder(this, _packageManagedObjectTypes);
    _entities = builder.entities;
    _tableDefinitionToEntityMap = builder.tableDefinitionToEntityMap;
  }

  static List<Type> get _packageManagedObjectTypes {
    final libraries = currentMirrorSystem().libraries.values.where(
        (lib) => lib.uri.scheme == "package" || lib.uri.scheme == "file");

    final types = libraries
        .expand((lib) => lib.declarations.values)
        .whereType<ClassMirror>()
        .where((decl) => decl.hasReflectedType)
        .map((decl) => decl.reflectedType)
        .where(_isTypeManagedObjectSubclass)
        .toList();

    return types;
  }

  static bool _isTypeManagedObjectSubclass(Type type) {
    final managedObjectMirror = reflectClass(ManagedObject);
    final mirror = reflectClass(type);
    if (!mirror.isSubclassOf(managedObjectMirror)) {
      return false;
    }

    if (mirror == managedObjectMirror) {
      return false;
    }

    // mirror.mixin: If this class is the result of a mixin application of the form S with M, returns a class mirror on M.
    // Otherwise returns a class mirror on the reflectee.
    if (mirror.mixin != mirror) {
      return false;
    }

    return true;
  }

  Iterable<ManagedEntity> get entities => _entities.values;
  Map<Type, ManagedEntity> _entities = {};
  Map<Type, ManagedEntity> _tableDefinitionToEntityMap = {};

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
    return _entities[type] ?? _tableDefinitionToEntityMap[type];
  }

  @override
  void documentComponents(APIDocumentContext context) {
    entities.forEach((e) => e.documentComponents(context));
  }
}

/// Thrown when a [ManagedDataModel] encounters an error.
class ManagedDataModelError extends Error {
  ManagedDataModelError(this.message);

  factory ManagedDataModelError.noPrimaryKey(ManagedEntity entity) {
    return ManagedDataModelError("Class '${_getPersistentClassName(entity)}'"
        " doesn't declare a primary key property or declares more than one primary key. All 'ManagedObject' subclasses "
        "must have a primary key. Usually, this means you want to add '@primaryKey int id;' "
        "to ${_getPersistentClassName(entity)}, but if you want more control over "
        "the type of primary key, declare the property as one of "
        "${ManagedType.supportedDartTypes.join(", ")} and "
        "add '@Column(primaryKey: true)' above it.");
  }

  factory ManagedDataModelError.invalidType(
      Symbol tableSymbol, Symbol propertySymbol) {
    return ManagedDataModelError("Property '${_getName(propertySymbol)}' on "
        "'${_getName(tableSymbol)}'"
        " has an unsupported type. This can occur when the type cannot be stored in a database, or when"
        " a relationship does not have a valid inverse. If this property is supposed to be a relationship, "
        " ensure the inverse property annotation is 'Relate(#${_getName(propertySymbol)}, ...)'."
        " If this is not supposed to be a relationship property, its type must be one of: ${ManagedType.supportedDartTypes.join(", ")}.");
  }

  factory ManagedDataModelError.invalidMetadata(
      String tableName, Symbol property) {
    return ManagedDataModelError("Relationship '${_getName(property)}' on "
        "'$tableName' "
        "cannot both have 'Column' and 'Relate' metadata. "
        "To add flags for indexing or nullability to a relationship, see the constructor "
        "for 'Relate'.");
  }

  factory ManagedDataModelError.missingInverse(
      String tableName,
      String instanceName,
      Symbol property,
      String destinationTableName,
      Symbol expectedProperty) {
    var expectedString = "Some property";
    if (expectedProperty != null) {
      expectedString = "'${_getName(expectedProperty)}'";
    }
    return ManagedDataModelError("Relationship '${_getName(property)}' on "
        "'${tableName}' has "
        "no inverse property. Every relationship must have an inverse. "
        "$expectedString on "
        "'${destinationTableName}'"
        "is supposed to exist, and it should be either a "
        "'${instanceName}' or"
        "'ManagedSet<${instanceName}>'.");
  }

  factory ManagedDataModelError.incompatibleDeleteRule(
      String tableName, Symbol property) {
    return ManagedDataModelError("Relationship '${_getName(property)}' on "
        "'$tableName' "
        "has both 'RelationshipDeleteRule.nullify' and 'isRequired' equal to true, which "
        "couldn't possibly be true at the same. 'isRequired' means the column "
        "can't be null and 'nullify' means the column has to be null.");
  }

  factory ManagedDataModelError.dualMetadata(String tableName, Symbol property,
      String destinationTableName, String inverseProperty) {
    return ManagedDataModelError("Relationship '${_getName(property)}' "
        "on '${tableName}' "
        "and '${inverseProperty}' "
        "on '${destinationTableName}' "
        "both have 'Relate' metadata, but only one can. "
        "The property with 'Relate' metadata is a foreign key column "
        "in the database.");
  }

  factory ManagedDataModelError.duplicateInverse(
      String tableName, String inverseName, List<String> conflictingNames) {
    return ManagedDataModelError(
        "Entity '${tableName}' has multiple relationship "
        "properties that claim to be the inverse of '$inverseName'. A property may "
        "only have one inverse. The claiming properties are: ${conflictingNames.join(", ")}.");
  }

  factory ManagedDataModelError.noDestinationEntity(
      String tableName, Symbol property, Symbol expectedType) {
    return ManagedDataModelError("Relationship '${_getName(property)}' on "
        "'${tableName}' expects that there is a subclass "
        "of 'ManagedObject' named '${_getName(expectedType)}', "
        "but there isn't one. If you have declared one - and you really checked "
        "hard for typos - make sure the file it is declared in is imported appropriately.");
  }

  factory ManagedDataModelError.multipleDestinationEntities(String tableName,
      Symbol property, List<String> possibleEntities, Symbol expected) {
    return ManagedDataModelError("Relationship '${_getName(property)}' on "
        "'${tableName}' expects that just one "
        "'ManagedObject' subclass uses a table definition that extends "
        "'${_getName(expected)}. But the following implementations were found: "
        "${possibleEntities.join(",")}. That's just "
        "how it is for now.");
  }

  factory ManagedDataModelError.invalidTransient(
      ManagedEntity entity, Symbol property) {
    return ManagedDataModelError(
        "Transient property '${_getName(property)}' on "
        "'${_getInstanceClassName(entity)}' declares that"
        "it is transient, but it it has a mismatch. A transient "
        "getter method must have 'isAvailableAsOutput' and a transient "
        "setter method must have 'isAvailableAsInput'.");
  }

  factory ManagedDataModelError.noConstructor(ClassMirror cm) {
    final name = _getName(cm.simpleName);
    return ManagedDataModelError("Invalid 'ManagedObject' subclass "
        "'$name' does not implement default, unnamed constructor. "
        "Add '$name();' to the class declaration.");
  }

  factory ManagedDataModelError.duplicateTables(
      String tableName, List<String> instanceTypes) {
    return ManagedDataModelError(
        "Entities ${instanceTypes.map((i) => "'$i'").join(",")} "
        "have the same table name: '$tableName'. Rename these "
        "the table definitions, or add a '@Table(name: ...)' annotation to the table definition.");
  }

  factory ManagedDataModelError.conflictingTypes(
      ManagedEntity entity, String propertyName) {
    return ManagedDataModelError(
        "The entity '${_getInstanceClassName(entity)}' declares two accessors named "
        "'$propertyName', but they have conflicting types.");
  }

  factory ManagedDataModelError.invalidValidator(
      ManagedEntity entity, String property, String reason) {
    return ManagedDataModelError("Type '${_getPersistentClassName(entity)}' "
        "has invalid validator for property '$property'. Reason: $reason");
  }

  factory ManagedDataModelError.emptyEntityUniqueProperties(String tableName) {
    return ManagedDataModelError("Type '$tableName' "
        "has empty set for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties).");
  }

  factory ManagedDataModelError.singleEntityUniqueProperty(
      String tableName, Symbol property) {
    return ManagedDataModelError("Type '$tableName' "
        "has only one attribute for unique 'Table'. Must contain two or "
        "more attributes (or belongs-to relationship properties). To make this property unique, "
        "add 'Column(unique: true)' to declaration of '${_getName(property)}'.");
  }

  factory ManagedDataModelError.invalidEntityUniqueProperty(
      String tableName, Symbol property) {
    return ManagedDataModelError("Type '${tableName}' "
        "declares '${MirrorSystem.getName(property)}' as unique in 'Table', "
        "but '${MirrorSystem.getName(property)}' is not a property of this type.");
  }

  factory ManagedDataModelError.relationshipEntityUniqueProperty(
      String tableName, Symbol property) {
    return ManagedDataModelError("Type '${tableName}' "
        "declares '${_getName(property)}' as unique in 'Table'. This property cannot "
        "be used to make an instance unique; only attributes or belongs-to relationships may used "
        "in this way.");
  }

  static String _getPersistentClassName(ManagedEntity entity) =>
      _getName(entity?.tableDefinition?.simpleName);

  static String _getInstanceClassName(ManagedEntity entity) =>
      _getName(entity?.instanceType?.simpleName);

  static String _getName(Symbol s) =>
      s != null ? MirrorSystem.getName(s) : null;

  final String message;

  @override
  String toString() {
    return "Data Model Error: $message";
  }
}
