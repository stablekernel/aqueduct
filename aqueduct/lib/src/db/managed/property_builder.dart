import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/attributes.dart';
import 'package:aqueduct/src/db/managed/entity_builder.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/db/managed/validation/managed.dart';
import 'package:aqueduct/src/db/managed/entity_mirrors.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

class PropertyBuilder {
  PropertyBuilder(this.entity, this.declaration)
      : relate = firstMetadataOfType(declaration),
        column = firstMetadataOfType(declaration),
        validators = validatorsFromDeclaration(declaration) {
    if (relate != null && column != null) {
      throw ManagedDataModelError.invalidMetadata(
          entity.tableDefinitionTypeName, declaration.simpleName);
    }
    _type = _getType();
    _relatedInstanceType = _getRelatedInstanceType();
    _relationshipType = _getRelationshipType();
    _name = _getName();
    serialize = _getTransienceForProperty();
  }

  final EntityBuilder entity;
  final DeclarationMirror declaration;
  final Relate relate;
  final Column column;
  final List<Validate> validators;
  Serialize serialize;

  String get name => _name;

  bool get isRelationship => relatedInstanceType != null;

  ManagedType get type => _type;

  ClassMirror get relatedInstanceType => _relatedInstanceType;

  PropertyBuilder get relatedProperty => _relatedProperty;

  ManagedRelationshipType get relationshipType => _relationshipType;
  PropertyBuilder _relatedProperty;

  ClassMirror _relatedInstanceType;

  String _name;
  ManagedType _type;
  ManagedAttributeDescription _attribute;
  ManagedRelationshipDescription _relationship;
  ManagedRelationshipType _relationshipType;

  void linkBuilders(List<EntityBuilder> others) {
    if (!isRelationship) {
      return;
    }

    // We only care about belongsTo, because we'll set both sides
    // of the relationship when we find it. We'll check for missing
    // relationships when the data model validates itself.
    if (relationshipType == ManagedRelationshipType.belongsTo) {
      final relatedEntityBuilder = _getRelatedBuilderFrom(others);
      _relatedProperty = _getInverseBuilderFrom(relatedEntityBuilder);
      _relatedProperty._relatedProperty = this;
    }
  }

  ManagedAttributeDescription getAttribute(ManagedEntity entity) {
    if (isRelationship) {
      return null;
    }
    return _attribute ??= ManagedAttributeDescription(
        entity, name, type, _getDeclarationType(),
        primaryKey: column?.isPrimaryKey ?? false,
        defaultValue: column?.defaultValue,
        unique: column?.isUnique ?? false,
        indexed: column?.isIndexed ?? false,
        nullable: column?.isNullable ?? false,
        includedInDefaultResultSet: !(column?.shouldOmitByDefault ?? false),
        autoincrement: column?.autoincrement ?? false,
        validators: validators);
  }

  ManagedRelationshipDescription getRelationship(ManagedEntity entity, List<ManagedEntity> others) {
    if (!isRelationship) {
      return null;
    }

    if (_relationship == null) {
      var destinationEntity = others.fir;
      var columnType =
        destinationEntity.attributes[destinationEntity.primaryKey].type;
      var unique = false;
      var required = false;
      var includeDefault = false;
      if (relationshipType == ManagedRelationshipType.belongsTo) {
        includeDefault = true;
        if (relatedProperty.relationshipType == ManagedRelationshipType.hasOne) {
          unique = true;
        }
        if (relate.isRequired) {
          required = true;
        }
      }

      _relationship = ManagedRelationshipDescription(
        entity,
        name,
        columnType,
        relatedInstanceType,
        destinationEntity,
        relate?.onDelete,
        relationshipType,
        Symbol(relatedProperty.name),
        unique: unique,
        indexed: true,
        nullable: !required,
        includedInDefaultResultSet: includeDefault);
    }

    return _relationship;
  }

  void validate() {
    if (relatedInstanceType == entity.instanceType) {
      throw ManagedDataModelError.cyclicReference(entity.instanceTypeName, name);
    }

    if (relate?.onDelete == DeleteRule.nullify &&
        (relate?.isRequired ?? false)) {
      throw ManagedDataModelError.incompatibleDeleteRule(
          entity.tableDefinitionTypeName, declaration.simpleName);
    }

    if (type == null) {
      throw ManagedDataModelError.invalidType(
          declaration.owner.simpleName, declaration.simpleName);
    }
  }

  ClassMirror _getDeclarationType() {
    final decl = declaration;
    TypeMirror type;
    if (decl is MethodMirror) {
      if (decl.isGetter) {
        type = decl.returnType;
      } else if (decl.isSetter) {
        type = decl.parameters.first.type;
      }
    } else if (decl is VariableMirror) {
      type = decl.type;
    }

    if (type is! ClassMirror) {
      throw ManagedDataModelError(
          "Invalid type for field '${MirrorSystem.getName(declaration.simpleName)}' "
          "in table definition '${entity.tableDefinitionTypeName}'.");
    }

    return type as ClassMirror;
  }

  ManagedType _getType() {
    final declType = _getDeclarationType();
    TypeMirror type;
    try {
      if (column?.databaseType != null) {
        return ManagedType.fromKind(column.databaseType);
      }

      return ManagedType(declType);
    } on UnsupportedError catch (e) {
      throw ManagedDataModelError("Invalid declaration "
          "'${MirrorSystem.getName(declaration.owner.simpleName)}.${MirrorSystem.getName(declaration.simpleName)}'. "
          "Reason: $e");
    }
  }

  String _getName() {
    if (declaration is MethodMirror) {
      if ((declaration as MethodMirror).isGetter) {
        return MirrorSystem.getName(declaration.simpleName);
      } else if ((declaration as MethodMirror).isSetter) {
        var name = MirrorSystem.getName(declaration.simpleName);
        return name.substring(0, name.length - 1);
      }
    } else if (declaration is VariableMirror) {
      return MirrorSystem.getName(declaration.simpleName);
    }

    throw ManagedDataModelError(
        "Tried getting property type description from non-property. This is an internal error, "
        "as this method shouldn't be invoked on non-property or non-accessors.");
  }

  Serialize _getTransienceForProperty() {
    Serialize metadata = firstMetadataOfType<Serialize>(declaration);
    if (declaration is VariableMirror) {
      return metadata;
    }

    MethodMirror m = declaration as MethodMirror;
    if (m.isGetter && metadata.isAvailableAsOutput) {
      return const Serialize(output: true, input: false);
    } else if (m.isSetter && metadata.isAvailableAsInput) {
      return const Serialize(input: true, output: false);
    }

    return null;
  }

  ClassMirror _getRelatedInstanceType() {
    final d = declaration;

    if (d is VariableMirror) {
      final modelMirror = reflectType(ManagedObject);
      final setMirror = reflectType(ManagedSet);

      if (d.type.isSubtypeOf(modelMirror)) {
        return d.type as ClassMirror;
      } else if (d.type.isSubtypeOf(setMirror)) {
        return d.type.typeArguments.first as ClassMirror;
      } else if (relate?.isDeferred ?? false) {
        return modelMirror as ClassMirror;
      }
    }

    return null;
  }

  EntityBuilder _getRelatedBuilderFrom(List<EntityBuilder> builders) {
    EntityBuilder relatedEntityBuilder;
    if (relate?.isDeferred ?? false) {
      final possibleEntities = builders.where((e) {
        return e.instanceType.isSubtypeOf(relatedInstanceType);
      }).toList();

      if (possibleEntities.length > 1) {
        throw ManagedDataModelError.multipleDestinationEntities(
            entity.tableDefinitionTypeName,
            declaration.simpleName,
            possibleEntities.map((e) => e.instanceTypeName).toList(),
            _getDeclarationType().simpleName);
      } else if (possibleEntities.length == 1) {
        relatedEntityBuilder = possibleEntities.first;
      }
    } else {
      relatedEntityBuilder = builders.firstWhere(
          (b) => b.tableDefinitionType == relatedInstanceType,
          orElse: () => null);
    }

    if (relatedEntityBuilder == null) {
      throw ManagedDataModelError.noDestinationEntity(
          entity.tableDefinitionTypeName,
          declaration.simpleName,
          relatedInstanceType.simpleName);
    }

    return relatedEntityBuilder;
  }

  PropertyBuilder _getInverseBuilderFrom(EntityBuilder relatedEntityBuilder) {
    PropertyBuilder inverse;
    if (relationshipType == ManagedRelationshipType.belongsTo) {
      inverse = relatedEntityBuilder.properties.firstWhere(
          (p) => p.name == MirrorSystem.getName(relate.inversePropertyName),
          orElse: () => null);

      if (inverse.relate != null) {
        throw ManagedDataModelError.dualMetadata(
            entity.tableDefinitionTypeName,
            declaration.simpleName,
            relatedEntityBuilder.tableDefinitionTypeName,
            inverse.name);
      }
    } else {
      inverse = relatedEntityBuilder.properties.firstWhere(
          (p) => p.relate?.inversePropertyName == declaration.simpleName,
          orElse: () => null);
    }

    if (inverse == null) {
      throw ManagedDataModelError.missingInverse(
          entity.tableDefinitionTypeName,
          entity.instanceTypeName,
          declaration.simpleName,
          relatedEntityBuilder.tableDefinitionTypeName,
          null);
    }

    return inverse;
  }

  ManagedRelationshipType _getRelationshipType() {
    if (isRelationship) {
      if (relate != null) {
        return ManagedRelationshipType.belongsTo;
      } else if (_getDeclarationType().isSubtypeOf(reflectType(ManagedSet))) {
        return ManagedRelationshipType.hasMany;
      } else {
        return ManagedRelationshipType.hasOne;
      }
    }

    return null;
  }
}
