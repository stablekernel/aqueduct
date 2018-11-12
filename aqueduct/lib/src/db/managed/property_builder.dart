import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/attributes.dart';
import 'package:aqueduct/src/db/managed/entity_builder.dart';
import 'package:aqueduct/src/db/managed/entity_mirrors.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

/*
Move all validation steps into validate.
Fix issue when compiling relationships, esp. deferred.
 */

class PropertyBuilder {
  PropertyBuilder(this.parent, this.declaration)
      : relate = firstMetadataOfType(declaration),
        column = firstMetadataOfType(declaration),
        validators = validatorsFromDeclaration(declaration),
        serialize = _getTransienceForProperty(declaration) {
    name = _getName();
    type = _getType();
  }

  final EntityBuilder parent;
  final DeclarationMirror declaration;
  final Relate relate;
  final Column column;
  final List<Validate> validators;
  Serialize serialize;

  ManagedAttributeDescription attribute;
  ManagedRelationshipDescription relationship;

  String name;
  ManagedType type;

  bool get isRelationship => relatedProperty != null;
  ManagedEntity destinationEntity;
  PropertyBuilder relatedProperty;
  ManagedRelationshipType relationshipType;
  bool primaryKey = false;
  String defaultValue;
  bool nullable = false;
  bool unique = false;
  bool includeInDefaultResultSet = true;
  bool indexed = false;
  bool autoincrement = false;
  DeleteRule deleteRule;

  void compile(List<EntityBuilder> others) {
    if (type == null) {
      if (relate != null) {
        relatedProperty =
            _getRelatedEntityBuilderFrom(others).getInverseOf(this);
        type = relatedProperty.parent.primaryKeyProperty.type;
        relationshipType = ManagedRelationshipType.belongsTo;
        includeInDefaultResultSet = true;
        deleteRule = relate.onDelete;
        nullable = !relate.isRequired;
        relatedProperty.setInverse(this);
        unique =
            relatedProperty?.relationshipType == ManagedRelationshipType.hasOne;
      }
    } else {
      primaryKey = column?.isPrimaryKey ?? false;
      defaultValue = column?.defaultValue;
      unique = column?.isUnique ?? false;
      indexed = column?.isIndexed ?? false;
      nullable = column?.isNullable ?? false;
      includeInDefaultResultSet = !(column?.shouldOmitByDefault ?? false);
      autoincrement = column?.autoincrement ?? false;
    }
  }

  void setInverse(PropertyBuilder foreignKey) {
    relatedProperty = foreignKey;
    includeInDefaultResultSet = false;

    if (getDeclarationType().isSubtypeOf(reflectType(ManagedSet))) {
      relationshipType = ManagedRelationshipType.hasMany;
    } else {
      relationshipType = ManagedRelationshipType.hasOne;
    }
  }

  void validate() {
    if (type == null) {
      if (!isRelationship ||
          relationshipType == ManagedRelationshipType.belongsTo) {
        throw ManagedDataModelError.invalidType(
            declaration.owner.simpleName, declaration.simpleName);
      }
    }

    if (isRelationship) {
      if (column != null) {
        throw ManagedDataModelError.invalidMetadata(
            parent.tableDefinitionTypeName, declaration.simpleName);
      }
      if (relate != null && relatedProperty.relate != null) {
        throw ManagedDataModelError.dualMetadata(
            parent.tableDefinitionTypeName,
            declaration.simpleName,
            relatedProperty.parent.tableDefinitionTypeName,
            relatedProperty.name);
      }
    } else {
      if (defaultValue != null && autoincrement) {
        throw ManagedDataModelError("Property '${parent.name}.$name' is invalid. "
          "A property cannot be both have a default value and be autoincrementing. ");
      }
    }

    if (relate?.onDelete == DeleteRule.nullify &&
        (relate?.isRequired ?? false)) {
      throw ManagedDataModelError.incompatibleDeleteRule(
          parent.tableDefinitionTypeName, declaration.simpleName);
    }
  }

  void link(List<ManagedEntity> others) {
    if (isRelationship) {
      var destinationEntity =
          others.firstWhere((e) => e == relatedProperty.parent.entity);

      relationship = ManagedRelationshipDescription(
          parent.entity,
          name,
          type,
          (declaration as VariableMirror).type as ClassMirror,
          destinationEntity,
          deleteRule,
          relationshipType,
          Symbol(relatedProperty.name),
          unique: unique,
          indexed: true,
          nullable: nullable,
          includedInDefaultResultSet: includeInDefaultResultSet);
    } else {
      attribute = ManagedAttributeDescription(
          parent.entity, name, type, getDeclarationType(),
          primaryKey: primaryKey,
          transientStatus: serialize,
          defaultValue: defaultValue,
          unique: unique,
          indexed: indexed,
          nullable: nullable,
          includedInDefaultResultSet: includeInDefaultResultSet,
          autoincrement: autoincrement,
          validators: validators);
    }
  }

  ClassMirror getDeclarationType() {
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
          "in table definition '${parent.tableDefinitionTypeName}'.");
    }

    return type as ClassMirror;
  }

  ManagedType _getType() {
    final declType = getDeclarationType();
    try {
      if (column?.databaseType != null) {
        return ManagedType.fromKind(column.databaseType);
      }

      return ManagedType(declType);
    } on UnsupportedError {
      return null;
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

  EntityBuilder _getRelatedEntityBuilderFrom(List<EntityBuilder> builders) {
    final expectedInstanceType = getDeclarationType();
    if (!relate.isDeferred) {
      return builders.firstWhere((b) => b.instanceType == expectedInstanceType,
          orElse: () {
        throw ManagedDataModelError.noDestinationEntity(
            parent.tableDefinitionTypeName,
            declaration.simpleName,
            expectedInstanceType.simpleName);
      });
    }

    final possibleEntities = builders.where((e) {
      return e.tableDefinitionType.isSubtypeOf(expectedInstanceType);
    }).toList();

    if (possibleEntities.length > 1) {
      throw ManagedDataModelError.multipleDestinationEntities(
          parent.tableDefinitionTypeName,
          declaration.simpleName,
          possibleEntities.map((e) => e.instanceTypeName).toList(),
          getDeclarationType().simpleName);
    } else if (possibleEntities.length == 1) {
      return possibleEntities.first;
    }

    throw ManagedDataModelError.noDestinationEntity(
        parent.tableDefinitionTypeName,
        declaration.simpleName,
        expectedInstanceType.simpleName);
  }

  static Serialize _getTransienceForProperty(DeclarationMirror declaration) {
    Serialize metadata = firstMetadataOfType<Serialize>(declaration);
    if (declaration is VariableMirror) {
      return metadata;
    }

    final m = declaration as MethodMirror;
    if (m.isGetter && metadata.isAvailableAsOutput) {
      return const Serialize(output: true, input: false);
    } else if (m.isSetter && metadata.isAvailableAsInput) {
      return const Serialize(input: true, output: false);
    }

    return null;
  }
}
