import 'dart:mirrors';

import 'query.dart';
import '../managed/managed.dart';
import '../persistent_store/persistent_store.dart';
import '../managed/query_matchable.dart';
import '../persistent_store/persistent_store_query.dart';

ManagedPropertyDescription _propertyForName(
    ManagedEntity entity, String propertyName) {
  var property = entity.properties[propertyName];
  if (property == null) {
    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
            "Property $propertyName does not exist on ${entity.tableName}");
  }
  if (property is ManagedRelationshipDescription &&
      property.relationshipType != ManagedRelationshipType.belongsTo) {
    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
            "Property $propertyName is a hasMany or hasOne relationship and is invalid as a result property of ${entity
            .tableName}, use matchOn.$propertyName.includeInResultSet = true instead.");
  }

  return property;
}

List<PersistentColumnMapping> mappingElementsForList(
    List<String> keys, ManagedEntity entity) {
  if (!keys.contains(entity.primaryKey)) {
    keys.add(entity.primaryKey);
  }

  return keys.map((key) {
    var property = _propertyForName(entity, key);
    return new PersistentColumnMapping(property, null);
  }).toList();
}

QueryPage validatePageDescriptor(ManagedEntity entity, QueryPage page) {
  if (page == null) {
    return null;
  }

  var prop = entity.attributes[page.propertyName];
  if (prop == null) {
    throw new QueryException(QueryExceptionEvent.requestFailure,
        message:
            "Property ${page.propertyName} in pageDescriptor does not exist on ${entity.tableName}.");
  }

  if (page.boundingValue != null &&
      !prop.isAssignableWith(page.boundingValue)) {
    throw new QueryException(QueryExceptionEvent.requestFailure,
        message:
            "Property ${page.propertyName} in pageDescriptor has invalid type (${page.boundingValue.runtimeType}).");
  }

  return page;
}

List<PersistentColumnMapping> mappingElementsForMap(
    Map<String, dynamic> valueMap, ManagedEntity entity) {
  return valueMap?.keys
      ?.map((key) {
        var property = entity.properties[key];
        if (property == null) {
          throw new QueryException(QueryExceptionEvent.requestFailure,
              message:
                  "Property $key in values does not exist on ${entity.tableName}");
        }

        var value = valueMap[key];
        if (property is ManagedRelationshipDescription) {
          if (property.relationshipType != ManagedRelationshipType.belongsTo) {
            return null;
          }

          if (value != null) {
            if (value is ManagedObject) {
              value = value[property.destinationEntity.primaryKey];
            } else if (value is Map) {
              value = value[property.destinationEntity.primaryKey];
            } else {
              throw new QueryException(QueryExceptionEvent.internalFailure,
                  message:
                      "Property $key on ${entity.tableName} in Query values must be a Map or ${MirrorSystem.getName(
                  property.destinationEntity.instanceType.simpleName)} ");
            }
          }
        }

        return new PersistentColumnMapping(property, value);
      })
      ?.where((m) => m != null)
      ?.toList();
}

List<PersistentJoinMapping> joinElementsFromQueryMatchable(
    QueryMatchableExtension matcherBackedObject,
    PersistentStore store,
    Map<Type, List<String>> nestedResultProperties) {
  var entity = matcherBackedObject.entity;
  var propertiesToJoin = matcherBackedObject.joinPropertyKeys;

  return propertiesToJoin
      .map((propertyName) {
        QueryMatchableExtension inner =
            matcherBackedObject.backingMap[propertyName];

        var relDesc = entity.relationships[propertyName];
        var predicate = new QueryPredicate.fromQueryIncludable(inner, store);
        var nestedProperties =
            nestedResultProperties[inner.entity.instanceType.reflectedType];
        var propertiesToFetch =
            nestedProperties ?? inner.entity.defaultProperties;

        var joinElements = [
          new PersistentJoinMapping(
              PersistentJoinType.leftOuter,
              relDesc,
              predicate,
              mappingElementsForList(propertiesToFetch, inner.entity))
        ];

        if (inner.hasJoinElements) {
          joinElements.addAll(joinElementsFromQueryMatchable(
              inner, store, nestedResultProperties));
        }

        return joinElements;
      })
      .expand((l) => l)
      .toList();
}
