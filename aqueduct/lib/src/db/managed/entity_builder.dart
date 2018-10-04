import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/attributes.dart';
import 'package:aqueduct/src/db/managed/data_model.dart';
import 'package:aqueduct/src/db/managed/entity_mirrors.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/object.dart';
import 'package:aqueduct/src/db/managed/property_builder.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:logging/logging.dart';

class EntityBuilder {
  EntityBuilder(ManagedDataModel dataModel, Type type)
      : instanceType = reflectClass(type),
        tableDefinitionType = _getTableDefinitionForType(type),
        metadata = firstMetadataOfType(_getTableDefinitionForType(type)) {
    name = _getName();
    entity = ManagedEntity(dataModel, name, instanceType, tableDefinitionType)
      ..validators = [];
    properties = _getProperties();
    primaryKeyProperty = properties.firstWhere((p) => p.column?.isPrimaryKey ?? false, orElse: () => null);
  }

  final ClassMirror instanceType;
  final ClassMirror tableDefinitionType;
  final Table metadata;

  Map<String, ManagedAttributeDescription> attributes = {};
  Map<String, ManagedRelationshipDescription> relationships = {};
  ManagedEntity entity;
  List<Validate> validators;
  List<PropertyBuilder> properties = [];
  List<String> uniquePropertySet;
  String name;

  PropertyBuilder primaryKeyProperty;

  String get instanceTypeName => MirrorSystem.getName(instanceType.simpleName);

  String get tableDefinitionTypeName =>
      MirrorSystem.getName(tableDefinitionType.simpleName);

  void compile(List<EntityBuilder> others) {
    validators = properties
        .map((builder) => builder.validators)
        .expand((e) => e)
        .toList();

    properties.forEach((p) {
      p.compile(others);
    });

    uniquePropertySet =
        metadata?.uniquePropertySet?.map(MirrorSystem.getName)?.toList();
  }

  void validate() {
    // Check that we have a default constructor
    if (!classHasDefaultConstructor(instanceType)) {
      throw ManagedDataModelError.noConstructor(instanceType);
    }

    // Check that we only have one primary key
    if (properties.where((pb) => pb.primaryKey).length != 1) {
      throw ManagedDataModelError.noPrimaryKey(entity);
    }

    // CHeck that our unique property set is valid
    if (uniquePropertySet != null) {
      if (uniquePropertySet.isEmpty) {
        throw ManagedDataModelError.emptyEntityUniqueProperties(
            tableDefinitionTypeName);
      } else if (uniquePropertySet.length == 1) {
        throw ManagedDataModelError.singleEntityUniqueProperty(
            tableDefinitionTypeName, metadata.uniquePropertySet.first);
      }

      uniquePropertySet.forEach((key) {
        final prop = properties.firstWhere((p) => p.name == key, orElse: () {
          throw ManagedDataModelError.invalidEntityUniqueProperty(
              tableDefinitionTypeName, Symbol(key));
        });

        if (prop.isRelationship &&
            prop.relationshipType != ManagedRelationshipType.belongsTo) {
          throw ManagedDataModelError.relationshipEntityUniqueProperty(
              tableDefinitionTypeName, Symbol(key));
        }
      });
    }

    // Check each property
    properties.forEach((p) => p.validate());
  }

  void link(List<ManagedEntity> entities) {
    entity.symbolMap = {};
    properties.forEach((p) {
      p.link(entities);

      entity.symbolMap[Symbol(p.name)] = p.name;
      entity.symbolMap[Symbol("${p.name}=")] = p.name;

      if (p.isRelationship) {
        relationships[p.name] = p.relationship;
      } else {
        attributes[p.name] = p.attribute;
        entity.validators.addAll(
            p.attribute.validators.map((v) => v.getValidator(p.attribute)));
        if (p.primaryKey) {
          entity.primaryKey = p.name;
        }
      }
    });

    entity.attributes = attributes;
    entity.relationships = relationships;
    entity.uniquePropertySet =
        uniquePropertySet?.map((key) => entity.properties[key])?.toList();
  }

  PropertyBuilder getInverseOf(PropertyBuilder foreignKey) {
    final expectedSymbol = foreignKey.relate.inversePropertyName;
    return properties.firstWhere(
        (p) => p.declaration.simpleName == expectedSymbol, orElse: () {
      throw ManagedDataModelError.missingInverse(
          foreignKey.parent.tableDefinitionTypeName,
          foreignKey.parent.instanceTypeName,
          foreignKey.declaration.simpleName,
          tableDefinitionTypeName,
          null);
    });
  }

  String _getName() {
    if (metadata?.name != null) {
      return metadata.name;
    }

    var declaredTableNameClass = classHierarchyForClass(tableDefinitionType)
        .firstWhere((cm) => cm.staticMembers[#tableName] != null,
            orElse: () => null);

    if (declaredTableNameClass == null) {
      return tableDefinitionTypeName;
    }

    Logger("aqueduct").warning(
        "Overriding ManagedObject.tableName is deprecated. Use '@Table(name: ...)' instead.");
    return declaredTableNameClass.invoke(#tableName, []).reflectee as String;
  }

  List<PropertyBuilder> _getProperties() {
    final transientProperties = _getTransientAttributes();
    final persistentProperties = instanceVariablesFromClass(tableDefinitionType)
        .map((p) => PropertyBuilder(this, p))
        .toList();

    return [transientProperties, persistentProperties]
        .expand((l) => l)
        .toList();
  }

  Iterable<PropertyBuilder> _getTransientAttributes() {
    final attributes = instanceType.declarations.values
        .where(isTransientPropertyOrAccessor)
        .map((declaration) => PropertyBuilder(this, declaration));

    final out = <PropertyBuilder>[];
    attributes.forEach((prop) {
      final complement =
          out.firstWhere((pb) => pb.name == prop.name, orElse: () => null);
      if (complement != null) {
        complement.serialize = const Serialize(input: true, output: true);
      } else {
        out.add(prop);
      }
    });

    return out;
  }

  static ClassMirror _getTableDefinitionForType(Type instanceType) {
    final ifNotFoundException = ManagedDataModelError(
        "Invalid instance type '$instanceType' '${reflectClass(instanceType).simpleName}' is not subclass of 'ManagedObject'.");

    return classHierarchyForClass(reflectClass(instanceType))
        .firstWhere(
            (cm) => !cm.superclass.isSubtypeOf(reflectType(ManagedObject)),
            orElse: () => throw ifNotFoundException)
        .typeArguments
        .first as ClassMirror;
  }
}
