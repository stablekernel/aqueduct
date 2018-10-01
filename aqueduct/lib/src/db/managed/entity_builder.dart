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
  EntityBuilder(Type type)
      : instanceType = reflectClass(type),
        tableDefinitionType = _getTableDefinitionForType(type),
        metadata = firstMetadataOfType(_getTableDefinitionForType(type)) {
    _name = _getName();
    _properties = _getProperties();
    _uniqueProperties = _getTableUniqueProperties();

    _validators = properties
        .map((builder) => builder.validators)
        .expand((e) => e)
        .toList();
  }

  final ClassMirror instanceType;
  final ClassMirror tableDefinitionType;

  final Table metadata;

  List<Validate> get validators => _validators;

  List<PropertyBuilder> get properties => _properties;

  List<String> get uniquePropertyNames =>
      _uniqueProperties.map((p) => p.name).toList();

  String get name => _name;

  String get instanceTypeName => MirrorSystem.getName(instanceType.simpleName);

  String get tableDefinitionTypeName =>
      MirrorSystem.getName(tableDefinitionType.simpleName);

  String _name;
  List<PropertyBuilder> _properties;
  List<PropertyBuilder> _uniqueProperties;
  List<Validate> _validators;
  ManagedEntity _entity;

  void linkBuilders(List<EntityBuilder> others) {
    final existing =
        others.firstWhere((placed) => placed.name == name, orElse: () => null);
    if (existing != null) {
      throw ManagedDataModelError.duplicateTables(
          existing.instanceTypeName, instanceTypeName, existing.name);
    }

    properties.forEach((p) {
      p.linkBuilders(others);
    });
  }

  void validate() {
    if (!classHasDefaultConstructor(instanceType)) {
      throw ManagedDataModelError.noConstructor(instanceType);
    }

    properties.forEach((p) => p.validate());
  }

  String _getName() {
    if (metadata.name != null) {
      return metadata.name;
    }

    var declaredTableNameClass = classHierarchyForClass(instanceType)
        .firstWhere((cm) => cm.staticMembers[#tableName] != null,
            orElse: () => null);

    if (declaredTableNameClass == null) {
      return instanceTypeName;
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
    var ifNotFoundException = ManagedDataModelError(
        "Invalid instance type '$instanceType' '${reflectClass(instanceType).simpleName}' is not subclass of 'ManagedObject'.");

    return classHierarchyForClass(reflectClass(instanceType))
        .firstWhere(
            (cm) => !cm.superclass.isSubtypeOf(reflectType(ManagedObject)),
            orElse: () => throw ifNotFoundException)
        .typeArguments
        .first as ClassMirror;
  }

  List<PropertyBuilder> _getTableUniqueProperties() {
    if (metadata?.uniquePropertySet != null) {
      if (metadata.uniquePropertySet.isEmpty) {
        throw ManagedDataModelError.emptyEntityUniqueProperties(
            tableDefinitionTypeName);
      } else if (metadata.uniquePropertySet.length == 1) {
        throw ManagedDataModelError.singleEntityUniqueProperty(
            tableDefinitionTypeName, metadata.uniquePropertySet.first);
      }

      return metadata.uniquePropertySet.map((sym) {
        final symbolName = MirrorSystem.getName(sym);
        var prop = properties.firstWhere((p) => p.name == symbolName,
            orElse: () => null);
        if (prop == null) {
          throw ManagedDataModelError.invalidEntityUniqueProperty(
              tableDefinitionTypeName, sym);
        }

        if (prop.isRelationship &&
            prop.relationshipType != ManagedRelationshipType.belongsTo) {
          throw ManagedDataModelError.relationshipEntityUniqueProperty(
              tableDefinitionTypeName, sym);
        }

        return prop;
      }).toList();
    }

    return null;
  }

  ManagedEntity getEntity(ManagedDataModel dataModel) {
    if (_entity == null) {
      _entity =
          ManagedEntity(dataModel, name, instanceType, tableDefinitionType);

      final validators = <ManagedValidator>[];
      Map<String, ManagedAttributeDescription> attributes = {};
      _properties.forEach((builder) {
        final prop = builder.getAttribute(_entity);
        if (prop != null) {
          attributes[prop.name] = prop;
          validators.addAll(prop.validators.map((v) => v.getValidator(prop)));
        }
      });

      _entity.attributes = attributes;
      _entity.uniquePropertySet = _entity.attributes.values
          .where((a) => uniquePropertyNames.contains(a.name))
          .toList();
      _entity.validators = validators;
    }

    return _entity;
  }

  void linkEntities(ManagedDataModel dataModel, List<ManagedEntity> entities) {
      final entity = getEntity(dataModel);
      entity.symbolMap = {};
      entity.attributes.forEach((name, _) {
        entity.symbolMap[Symbol(name)] = name;
        entity.symbolMap[Symbol("$name=")] = name;
      });
      entity.relationships.forEach((name, _) {
        entity.symbolMap[Symbol(name)] = name;
        entity.symbolMap[Symbol("$name=")] = name;
      });
  }
}
