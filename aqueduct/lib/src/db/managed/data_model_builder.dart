import 'dart:mirrors';

import 'package:aqueduct/src/db/managed/entity_builder.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

import 'entity_mirrors.dart';
import 'managed.dart';
import 'relationship_type.dart';

class DataModelBuilder {
  DataModelBuilder(ManagedDataModel dataModel, List<Type> instanceTypes) {
    _builders = instanceTypes.map((t) => EntityBuilder(dataModel, t)).toList();
    _builders.forEach((b) {
      b.compile(_builders.where((i) => i != b).toList());
    });
    _validate();

    _builders.forEach((b) {
      b.link(_builders.map((eb) => eb.entity).toList());

      final entity = b.entity;
      entities[entity.instanceType.reflectedType] = entity;
      tableDefinitionToEntityMap[entity.tableDefinition.reflectedType] = entity;
    });
  }

  Map<Type, ManagedEntity> entities = {};
  Map<Type, ManagedEntity> tableDefinitionToEntityMap = {};
  List<EntityBuilder> _builders;

  void _validate() {
    // Check for dupe tables
    _builders.forEach((builder) {
      final withSameName = _builders.where((eb) => eb.name == builder.name).map((eb) => eb.instanceTypeName).toList();
      if (withSameName.length > 1) {
        throw ManagedDataModelError.duplicateTables(builder.name, withSameName);
      }
    });

    _builders.forEach((b) => b.validate());
  }

//  ManagedRelationshipDescription relationshipForForeignKeyProperty(
//      ManagedEntity owningEntity,
//      ManagedEntity destinationEntity,
//      VariableMirror property) {
//
//    var columnType =
//        destinationEntity.attributes[destinationEntity.primaryKey].type;
//
//    return ManagedRelationshipDescription(
//        owningEntity,
//        MirrorSystem.getName(property.simpleName),
//        columnType,
//        property.type as ClassMirror,
//        destinationEntity,
//        relationship.onDelete,
//        ManagedRelationshipType.belongsTo,
//        inverseProperty.simpleName,
//        unique: !inverseProperty.type.isSubtypeOf(reflectType(ManagedSet)),
//        indexed: true,
//        nullable: !relationship.isRequired,
//        includedInDefaultResultSet: true);
//  }
//
//  ManagedRelationshipDescription relationshipDescriptionForHasManyOrOneProperty(
//      ManagedEntity owningEntity,
//      ManagedEntity destinationEntity,
//      VariableMirror property) {
//
//    var columnType =
//        destinationEntity.attributes[destinationEntity.primaryKey].type;
//
//    return ManagedRelationshipDescription(
//        owningEntity,
//        MirrorSystem.getName(property.simpleName),
//        columnType,
//        property.type as ClassMirror,
//        destinationEntity,
//        managedRelationship?.onDelete,
//        relType,
//        inverseProperty.simpleName,
//        unique: false,
//        indexed: true,
//        nullable: false,
//        includedInDefaultResultSet: false);
//  }
//
//  ManagedEntity matchingEntityForProperty(
//      ManagedEntity owningEntity, VariableMirror property) {
//    var typeMirror = property.type;
//    if (property.type.isSubtypeOf(reflectType(ManagedSet))) {
//      typeMirror = typeMirror.typeArguments.first;
//    }
//
//    var destinationEntity = entities[typeMirror.reflectedType];
//    if (destinationEntity == null) {
//      var relationshipMetadata = relationshipMetadataFromProperty(property);
//      if (relationshipMetadata.isDeferred) {
//        // Then we can scan for a list of possible entities that extend
//        // the interface.
//        var possibleEntities = entities.values.where((me) {
//          return me.tableDefinition.isSubtypeOf(typeMirror);
//        }).toList();
//
//        if (possibleEntities.isEmpty) {
//          throw ManagedDataModelError.noDestinationEntity(
//              owningEntity, property.simpleName);
//        } else if (possibleEntities.length > 1) {
//          throw ManagedDataModelError.multipleDestinationEntities(
//              owningEntity, property.simpleName, possibleEntities);
//        }
//
//        destinationEntity = possibleEntities.first;
//      } else {
//        throw ManagedDataModelError.noDestinationEntity(
//            owningEntity, property.simpleName);
//      }
//    }
//
//    return destinationEntity;
//  }
//
//  List<VariableMirror> propertiesFromEntityWithType(
//      ManagedEntity entity, TypeMirror type) {
//    return instanceVariablesFromClass(entity.tableDefinition).where((p) {
//      if (p.type.isSubtypeOf(type)) {
//        return true;
//      }
//
//      if (p.type.isSubtypeOf(reflectType(ManagedSet)) &&
//          p.type.typeArguments.first.isSubtypeOf(type)) {
//        return true;
//      }
//
//      return false;
//    }).toList();
//  }
//
//  VariableMirror inverseRelationshipProperty(ManagedEntity owningEntity,
//      ManagedEntity destinationEntity, VariableMirror property) {
//    var metadata = relationshipMetadataFromProperty(property);
//    if (metadata != null) {
//      // This is the belongs to side. Looking for the has-a side, which has an explicit inverse.
//      if (!metadata.isDeferred) {
//        var destinationProperty = instanceVariableFromClass(
//            destinationEntity.tableDefinition, metadata.inversePropertyName);
//        if (destinationProperty == null) {
//          throw ManagedDataModelError.missingInverse(
//              owningEntity, property.simpleName, destinationEntity, null);
//        }
//
//        if (relationshipMetadataFromProperty(destinationProperty) != null) {
//          throw ManagedDataModelError.dualMetadata(
//              owningEntity,
//              property.simpleName,
//              destinationEntity,
//              destinationProperty.simpleName);
//        }
//
//        return destinationProperty;
//      } else {
//        // This is the belongs to side. Looking for the has-a side, but it is deferred.
//        var candidates = propertiesFromEntityWithType(
//            destinationEntity, owningEntity.instanceType);
//        if (candidates.isEmpty) {
//          throw ManagedDataModelError.missingInverse(
//              owningEntity, property.simpleName, destinationEntity, null);
//        } else if (candidates.length > 1) {
//          throw ManagedDataModelError.duplicateInverse(
//              owningEntity,
//              property.simpleName,
//              destinationEntity,
//              candidates.map((v) => v.simpleName).toList());
//        }
//
//        return candidates.first;
//      }
//    } else {
//      // This is the has-a side. Looking for the belongs to side, which might be deferred on the other side
//      // If we have an explicit inverse, look for that first.
//      var candidates =
//          instanceVariablesFromClass(destinationEntity.tableDefinition)
//              .where((p) => relationshipMetadataFromProperty(p) != null)
//              .toList();
//
//      if (candidates.isEmpty) {
//        throw ManagedDataModelError.missingInverse(
//            owningEntity, property.simpleName, destinationEntity, null);
//      }
//
//      var specificInverses = candidates.where((p) {
//        return relationshipMetadataFromProperty(p).inversePropertyName ==
//                property.simpleName &&
//            owningEntity.instanceType.isSubtypeOf(p.type);
//      }).toList();
//      if (specificInverses.length == 1) {
//        return specificInverses.first;
//      } else if (specificInverses.length > 1) {
//        throw ManagedDataModelError.duplicateInverse(
//            owningEntity,
//            property.simpleName,
//            destinationEntity,
//            candidates.map((vm) => vm.simpleName).toList());
//      }
//
//      // We may be deferring, so check for those and make sure the types match up.
//      var deferredCandidates = candidates
//          .where((p) => relationshipMetadataFromProperty(p).isDeferred)
//          .where((p) => owningEntity.tableDefinition.isSubtypeOf(p.type))
//          .toList();
//      if (deferredCandidates.isEmpty) {
//        VariableMirror candidate;
//        if (candidates.isNotEmpty) {
//          candidate = candidates.first;
//        }
//        throw ManagedDataModelError.missingInverse(owningEntity,
//            property.simpleName, destinationEntity, candidate?.simpleName);
//      }
//
//      if (deferredCandidates.length > 1) {
//        throw ManagedDataModelError.duplicateInverse(
//            owningEntity,
//            property.simpleName,
//            destinationEntity,
//            candidates.map((v) => v.simpleName).toList());
//      }
//
//      return deferredCandidates.first;
//    }
//  }


}
