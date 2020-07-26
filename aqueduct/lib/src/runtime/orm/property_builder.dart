import 'dart:mirrors';

import 'package:aqueduct/src/runtime/orm/data_model_compiler.dart';
import 'package:aqueduct/src/runtime/orm/entity_builder.dart';
import 'package:aqueduct/src/runtime/orm/validator_builder.dart';
import 'package:aqueduct/src/runtime/orm/entity_mirrors.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

class PropertyBuilder {
  PropertyBuilder(this.parent, this.declaration)
      : relate = firstMetadataOfType(declaration),
        column = firstMetadataOfType(declaration),
        serialize = _getTransienceForProperty(declaration) {
    name = _getName();
    type = _getType();


    /* this collection of validators via 1. Validate metadata 2. Column metadata 3. implicit enum
    * is replicated in the generated code. if more implicit validators are created, a more general
    * purpose solution should be created
    * */
    _validators = validatorsFromDeclaration(declaration)
        .map((v) => ValidatorBuilder(this, v))
        .toList();

    if (column?.validators?.isNotEmpty ?? false) {
      _validators
          .addAll(column.validators.map((v) => ValidatorBuilder(this, v)));
    }

    if (type?.isEnumerated ?? false) {
      _validators.add(ValidatorBuilder(
          this, Validate.oneOf(type.enumerationMap.values.toList())));
    }
  }

  final EntityBuilder parent;
  final DeclarationMirror declaration;
  final Relate relate;
  final Column column;

  List<ValidatorBuilder> get validators => _validators;
  Serialize serialize;

  ManagedAttributeDescription attribute;
  ManagedRelationshipDescription relationship;
  List<ManagedValidator> managedValidators = [];

  String name;
  ManagedType type;

  bool get isRelationship => relatedProperty != null;
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
  List<ValidatorBuilder> _validators;

  void compile(List<EntityBuilder> entityBuilders) {
    if (type == null) {
      if (relate != null) {
        relatedProperty =
            _getRelatedEntityBuilderFrom(entityBuilders).getInverseOf(this);
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

    validators.forEach((vb) => vb.compile(entityBuilders));
  }

  void validate(List<EntityBuilder> entityBuilders) {
    if (type == null) {
      if (!isRelationship ||
          relationshipType == ManagedRelationshipType.belongsTo) {
        throw ManagedDataModelErrorImpl.invalidType(
            declaration.owner.simpleName, declaration.simpleName);
      }
    }

    if (isRelationship) {
      if (column != null) {
        throw ManagedDataModelErrorImpl.invalidMetadata(
            parent.tableDefinitionTypeName, declaration.simpleName);
      }
      if (relate != null && relatedProperty.relate != null) {
        throw ManagedDataModelErrorImpl.dualMetadata(
            parent.tableDefinitionTypeName,
            declaration.simpleName,
            relatedProperty.parent.tableDefinitionTypeName,
            relatedProperty.name);
      }
    } else {
      if (defaultValue != null && autoincrement) {
        throw ManagedDataModelError(
            "Property '${parent.name}.$name' is invalid. "
            "A property cannot have a default value and be autoincrementing. ");
      }
    }

    if (relate?.onDelete == DeleteRule.nullify &&
        (relate?.isRequired ?? false)) {
      throw ManagedDataModelErrorImpl.incompatibleDeleteRule(
          parent.tableDefinitionTypeName, declaration.simpleName);
    }

    validators.forEach((vb) => vb.validate(entityBuilders));
  }

  void link(List<ManagedEntity> others) {
    validators.forEach((v) => v.link(others));
    if (isRelationship) {
      var destinationEntity =
          others.firstWhere((e) => e == relatedProperty.parent.entity);

      final dartType =
          ((declaration as VariableMirror).type as ClassMirror).reflectedType;
      relationship = ManagedRelationshipDescription(
          parent.entity,
          name,
          type,
          dartType,
          destinationEntity,
          deleteRule,
          relationshipType,
          relatedProperty.name,
          unique: unique,
          indexed: true,
          nullable: nullable,
          includedInDefaultResultSet: includeInDefaultResultSet,
          validators: validators.map((v) => v.managedValidator).toList());
    } else {
      final dartType = getDeclarationType().reflectedType;
      attribute = ManagedAttributeDescription(parent.entity, name, type,
          dartType,
          primaryKey: primaryKey,
          transientStatus: serialize,
          defaultValue: defaultValue,
          unique: unique,
          indexed: indexed,
          nullable: nullable,
          includedInDefaultResultSet: includeInDefaultResultSet,
          autoincrement: autoincrement,
          validators: validators.map((v) => v.managedValidator).toList());
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
        return ManagedType(
            declType.reflectedType, column.databaseType, null, null);
      }

      return getManagedTypeFromType(declType);
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
        throw ManagedDataModelErrorImpl.noDestinationEntity(
            parent.tableDefinitionTypeName,
            declaration.simpleName,
            expectedInstanceType.simpleName);
      });
    }

    final possibleEntities = builders.where((e) {
      return e.tableDefinitionType.isSubtypeOf(expectedInstanceType);
    }).toList();

    if (possibleEntities.length > 1) {
      throw ManagedDataModelErrorImpl.multipleDestinationEntities(
          parent.tableDefinitionTypeName,
          declaration.simpleName,
          possibleEntities.map((e) => e.instanceTypeName).toList(),
          getDeclarationType().simpleName);
    } else if (possibleEntities.length == 1) {
      return possibleEntities.first;
    }

    throw ManagedDataModelErrorImpl.noDestinationEntity(
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