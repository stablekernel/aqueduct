import 'dart:mirrors';
import 'managed.dart';
import '../../utilities/mirror_helpers.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    instanceTypes.forEach((type) {
      var backingMirror = backingMirrorForType(type);
      var entity = new ManagedEntity(
          dataModel,
          tableNameForPersistentTypeMirror(backingMirror),
          reflectClass(type),
          backingMirror);
      entities[type] = entity;
      persistentTypeToEntityMap[entity.persistentType.reflectedType] = entity;

      entity.attributes = attributeMapForEntity(entity);
    });

    entities.forEach((_, entity) {
      entity.relationships = relationshipMapForEntity(entity);
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> persistentTypeToEntityMap = {};

  String tableNameForPersistentTypeMirror(ClassMirror typeMirror) {
    var tableNameSymbol = #tableName;

    var ptr = typeMirror;
    while (ptr.superclass != null) {
      if (ptr.staticMembers[tableNameSymbol] != null) {
        return ptr.invoke(tableNameSymbol, []).reflectee;
      }
      ptr = ptr.superclass;
    }

    return MirrorSystem.getName(typeMirror.simpleName);
  }

  Map<String, ManagedAttributeDescription> attributeMapForEntity(
      ManagedEntity entity) {
    Map<String, ManagedAttributeDescription> map = {};

    var transientProperties = entity.instanceType.declarations.values
        .where(isInstanceVariableMirror)
        .where(hasTransientMetadata)
        .map((dm) =>  attributeFromVariableMirror(entity, dm));

    var transientAccessors = entity.instanceType.declarations.values
        .where(isTransientAccessorMethod)
        .map((declMir) => attributeFromMethodMirror(entity, declMir));

    var persisentProperties = instanceVariableMirrorsFromClass(entity.persistentType)
      .where((declMir) => !doesVariableMirrorRepresentRelationship(declMir))
      .where((declMir) => !map.containsKey(MirrorSystem.getName(declMir.simpleName)))
      .map((declMir) => attributeFromVariableMirror(entity, declMir));

    return [transientProperties, transientAccessors, persisentProperties]
        .expand((l) => l)
        .fold({}, (map, attribute) {
          if (map.containsKey(attribute.name)) {
            // If we have split accessor methods to represent one transient property,
            // then we need to combine them here.
            map[attribute.name] = new ManagedAttributeDescription.transient(
                entity, attribute.name, attribute.type, managedTransientAttribute);
          } else {
            map[attribute.name] = attribute;
          }
          return map;
        });
  }

  ManagedAttributeDescription attributeFromMethodMirror(
      ManagedEntity entity, MethodMirror methodMirror) {
    var name = MirrorSystem.getName(methodMirror.simpleName);
    var dartTypeMirror = methodMirror.returnType;
    if (methodMirror.isSetter) {
      name = name.substring(0, name.length - 1);
      dartTypeMirror = methodMirror.parameters.first.type;
    }

    // We don't care about the mappable on the declaration when we specify it to the AttributeDescription,
    // only whether or not it is a getter/setter.
    return new ManagedAttributeDescription.transient(
        entity,
        name,
        ManagedPropertyDescription
            .propertyTypeForDartType(dartTypeMirror.reflectedType),
        new ManagedTransientAttribute(
            availableAsInput: methodMirror.isSetter,
            availableAsOutput: methodMirror.isGetter));
  }

  ManagedAttributeDescription attributeFromVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    if (entity.instanceType == mirror.owner) {
      // This attribute is declared in the instance type.
      var name = MirrorSystem.getName(mirror.simpleName);
      var type = ManagedPropertyDescription
          .propertyTypeForDartType(mirror.type.reflectedType);

      if (type == null) {
        throw new ManagedDataModelException(
            "Property '$name' on '${MirrorSystem.getName(entity.instanceType.simpleName)}' has invalid type");
      }

      return new ManagedAttributeDescription.transient(
          entity, name, type, transientFromDeclaration(mirror));
    } else {
      // This attribute is declared in the persistent type.
      var attributes = attributeMetadataFromDeclaration(mirror);
      var type = attributes?.databaseType ??
          ManagedPropertyDescription
              .propertyTypeForDartType(mirror.type.reflectedType);

      if (type == null) {
        throw new ManagedDataModelException(
            "Property '${MirrorSystem.getName(mirror.simpleName)}' on "
            "'${MirrorSystem.getName(entity.persistentType.simpleName)}' has no type information");
      }

      return new ManagedAttributeDescription(
          entity, MirrorSystem.getName(mirror.simpleName), type,
          primaryKey: attributes?.isPrimaryKey ?? false,
          defaultValue: attributes?.defaultValue ?? null,
          unique: attributes?.isUnique ?? false,
          indexed: attributes?.isIndexed ?? false,
          nullable: attributes?.isNullable ?? false,
          includedInDefaultResultSet: !(attributes?.shouldOmitByDefault ?? false),
          autoincrement: attributes?.autoincrement ?? false);
    }
  }

  Map<String, ManagedRelationshipDescription> relationshipMapForEntity(
      ManagedEntity entity) {
    return instanceVariableMirrorsFromClass(entity.persistentType)
        .where(doesVariableMirrorRepresentRelationship)
        .fold({}, (map, declMirror) {
          map[MirrorSystem.getName(declMirror.simpleName)] =
              relationshipFromVariableMirror(entity, declMirror);
          return map;
        });
  }

  ManagedRelationshipDescription relationshipFromVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    if (attributeMetadataFromDeclaration(mirror) != null) {
      throw new ManagedDataModelException(
          "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on "
          "'${MirrorSystem.getName(entity.persistentType.simpleName)}' "
          "must not define additional Attributes");
    }

    var destinationEntity = destinationEntityForVariableMirror(entity, mirror);
    var belongsToAttr = managedRelationshipMetadataFromDeclaration(mirror);
    var referenceProperty =
        destinationEntity.attributes[destinationEntity.primaryKey];

    if (belongsToAttr != null) {
      var inverseKey = belongsToAttr.inverseKey;
      var destinationVariableMirror = variableMirrorFromClass(destinationEntity.persistentType, inverseKey);

      if (destinationVariableMirror == null) {
        throw new ManagedDataModelException(
            "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on "
            "'${MirrorSystem.getName(entity.persistentType.simpleName)}' has "
            "no inverse. Expected '${MirrorSystem.getName(inverseKey)}' "
            "to be property on '${MirrorSystem.getName(destinationEntity.persistentType.simpleName)}'.");
      }

      if (belongsToAttr.onDelete == ManagedRelationshipDeleteRule.nullify &&
          belongsToAttr.isRequired) {
        throw new ManagedDataModelException(
            "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on '${entity.tableName}' "
            "set to nullify on delete, but is not nullable");
      }

      if (managedRelationshipMetadataFromDeclaration(destinationVariableMirror) != null) {
        throw new ManagedDataModelException(
            "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on "
            "'${entity.tableName}' and '${MirrorSystem.getName(destinationVariableMirror.simpleName)}' "
            "on '${destinationEntity.tableName}' have @ManagedRelationship metadata, only one may belong to the other.");
      }

      return new ManagedRelationshipDescription(
          entity,
          MirrorSystem.getName(mirror.simpleName),
          referenceProperty.type,
          destinationEntity,
          belongsToAttr.onDelete,
          ManagedRelationshipType.belongsTo,
          inverseKey,
          unique: !destinationVariableMirror.type.isSubtypeOf(reflectType(ManagedSet)),
          indexed: true,
          nullable: !belongsToAttr.isRequired,
          includedInDefaultResultSet: true);
    }

    VariableMirror inversePropertyMirror =
      instanceVariableMirrorsFromClass(destinationEntity.persistentType)
        .firstWhere((DeclarationMirror destinationDeclarationMirror) {
          if (destinationDeclarationMirror is VariableMirror) {
            var inverseBelongsToAttr =
                managedRelationshipMetadataFromDeclaration(destinationDeclarationMirror);
            var matchesInverseKey =
                inverseBelongsToAttr?.inverseKey == mirror.simpleName;

            var hasRightType = entity
                .instanceType.isSubtypeOf(destinationDeclarationMirror.type);

            if (matchesInverseKey && hasRightType) {
              return true;
            }
          }

          return false;
        }, orElse: () => null);

    if (inversePropertyMirror == null) {
      throw new ManagedDataModelException(
          "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on '${entity.tableName}' "
          "has no inverse declared in '${MirrorSystem.getName(destinationEntity.persistentType.simpleName)}' of appropriate type.");
    }

    var relType = ManagedRelationshipType.hasOne;
    if (mirror.type.isSubtypeOf(reflectType(ManagedSet))) {
      relType = ManagedRelationshipType.hasMany;
    }

    return new ManagedRelationshipDescription(
        entity,
        MirrorSystem.getName(mirror.simpleName),
        referenceProperty.type,
        destinationEntity,
        belongsToAttr?.onDelete,
        relType,
        inversePropertyMirror.simpleName,
        unique: false,
        indexed: true,
        nullable: false,
        includedInDefaultResultSet: false);
  }

  ManagedEntity destinationEntityForVariableMirror(
      ManagedEntity entity, VariableMirror mirror) {
    var typeMirror = mirror.type;
    if (mirror.type.isSubtypeOf(reflectType(ManagedSet))) {
      typeMirror = typeMirror.typeArguments.first;
    }

    var destinationEntity = entities[typeMirror.reflectedType];
    if (destinationEntity == null) {
      // Maybe its a superclass?
      var possibleEntities = entities.values.where((me) {
        return me.persistentType.isSubtypeOf(typeMirror);
      }).toList();

      if (possibleEntities.length == 0) {
        throw new ManagedDataModelException(
            "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on "
            "'${MirrorSystem.getName(entity.persistentType.simpleName)}' expects a destination"
            "ManagedEntity with persistentType '${MirrorSystem.getName(typeMirror.simpleName)}',"
            "but that entity does not exist. Was it's ManagedObject subclass included when creating this ManagedDataModel?");
      } else if (possibleEntities.length > 1) {
        throw new ManagedDataModelException(
            "Relationship '${MirrorSystem.getName(mirror.simpleName)}' on "
            "'${MirrorSystem.getName(entity.persistentType.simpleName)}' expects a destination"
            "ManagedEntity with persistentType '${MirrorSystem.getName(typeMirror.simpleName)}',"
            "but more than one entity implements this type.");
      } else {
        destinationEntity = possibleEntities.first;
      }
    }

    return destinationEntity;
  }

  ClassMirror backingMirrorForType(Type instanceType) {
    var rt = reflectClass(instanceType);
    var modelRefl = reflectType(ManagedObject);
    var entityTypeRefl = rt;

    while (rt.superclass.isSubtypeOf(modelRefl)) {
      rt = rt.superclass;
      entityTypeRefl = rt;
    }

    if (rt.isSubtypeOf(modelRefl)) {
      entityTypeRefl = entityTypeRefl.typeArguments.first;
    } else {
      throw new ManagedDataModelException(
          "Invalid instance type '$instanceType' '${reflectClass(instanceType).simpleName}'");
    }

    return entityTypeRefl;
  }
}

List<VariableMirror> instanceVariableMirrorsFromClass(ClassMirror classMirror) {
  var list = <VariableMirror>[];
  var persistentTypePtr = classMirror;
  while (persistentTypePtr.superclass != null) {
    var varMirrorsForThisType = persistentTypePtr.declarations.values
        .where(isInstanceVariableMirror)
        .map((declMir) => declMir as VariableMirror);

    list.addAll(varMirrorsForThisType);

    persistentTypePtr = persistentTypePtr.superclass;
  }

  return list;
}

VariableMirror variableMirrorFromClass(ClassMirror classMirror, Symbol name) {
  var persistentTypePtr = classMirror;
  while (persistentTypePtr.superclass != null) {
    var declaration = persistentTypePtr.declarations[name];
    if (declaration != null) {
      return declaration;
    }
    persistentTypePtr = persistentTypePtr.superclass;
  }

  return null;
}

bool isInstanceVariableMirror(DeclarationMirror mirror) =>
  mirror is VariableMirror && !mirror.isStatic;

bool hasTransientMetadata(DeclarationMirror mirror) =>
  transientFromDeclaration(mirror) != null;

bool isTransientAccessorMethod(DeclarationMirror declMir) {
  if (declMir is! MethodMirror) {
    return false;
  }

  var methodMirror = declMir as MethodMirror;
  if (methodMirror.isStatic) {
    return false;
  }

  if (!(methodMirror.isSetter || methodMirror.isGetter) || methodMirror.isSynthetic) {
    return false;
  }

  var mapMetadata = transientFromDeclaration(declMir);
  if (mapMetadata == null) {
    return false;
  }

  // A setter must be available as an input ONLY, a getter must be available as an output. This is confusing.
  return (methodMirror.isSetter && mapMetadata.isAvailableAsInput)
      || (methodMirror.isGetter && mapMetadata.isAvailableAsOutput);
}