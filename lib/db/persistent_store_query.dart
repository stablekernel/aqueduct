part of aqueduct;

enum JoinType {
  leftOuter
}


class PersistentStoreQuery {
  PersistentStoreQuery(this.rootEntity, PersistentStore store, Query q) {
    confirmQueryModifiesAllInstancesOnDeleteOrUpdate = q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
    timeoutInSeconds = q.timeoutInSeconds;
    sortDescriptors = q.sortDescriptors;
    resultKeys = _mappingElementsForList((q.resultProperties ?? rootEntity.defaultProperties), rootEntity);

    if (q._matchOn != null) {
      predicate = new Predicate._fromQueryIncludable(q._matchOn, store);
    } else {
      predicate = q.predicate;
    }

    if (q._matchOn?._hasJoinElements ?? false) {
      var joinElements = _joinElementsFromQueryMatchable(q.matchOn, store, q.nestedResultProperties);
      resultKeys.addAll(joinElements);
    } else {
      fetchLimit = q.fetchLimit;
      offset = q.offset;
      pageDescriptor = q.pageDescriptor;

      values = _mappingElementsForMap((q.valueMap ?? q.values?.backingMap), rootEntity);
    }
  }

  int offset = 0;
  int fetchLimit = 0;
  int timeoutInSeconds = 30;
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
  ModelEntity rootEntity;
  QueryPage pageDescriptor;
  Predicate predicate;
  List<SortDescriptor> sortDescriptors;
  List<MappingElement> values;
  List<MappingElement> resultKeys;

  static List<MappingElement> _mappingElementsForList(List<String> keys, ModelEntity entity) {
    if (!keys.contains(entity.primaryKey)) {
      keys.add(entity.primaryKey);
    }

    return keys.map((key) {
      var property = entity.properties[key];
      if (property == null) {
        throw new QueryException(500, "Property $key in resultKeys does not exist on ${entity.tableName}", -1);
      }
      if (property is RelationshipDescription && property.relationshipType != RelationshipType.belongsTo) {
        throw new QueryException(500, "Property $key in resultKeys is a hasMany or hasOne relationship and is invalid on ${entity.tableName}", -1);
      }

      return new MappingElement(property, null);
    }).toList();
  }

  List<MappingElement> _mappingElementsForMap(Map<String, dynamic> valueMap, ModelEntity entity) {
    return valueMap?.keys?.map((key) {
      var property = entity.properties[key];
      if (property == null) {
        throw new QueryException(400, "Property $key in values does not exist on ${entity.tableName}", -1);
      }

      var value = valueMap[key];
      if (property is RelationshipDescription) {
        if (property.relationshipType != RelationshipType.belongsTo) {
          return null;
        }

        if (value != null) {
          if (value is Model) {
            value = value[property.destinationEntity.primaryKey];
          } else if (value is Map) {
            value = value[property.destinationEntity.primaryKey];
          } else {
            throw new QueryException(500, "Property $key on ${entity.tableName} in Query values must be a Map or ${MirrorSystem.getName(property.destinationEntity.instanceType.simpleName)} ", -1);
          }
        }
      }

      return new MappingElement(property, value);
    })
    ?.where((m) => m != null)
    ?.toList();
  }

  static List<JoinMappingElement> _joinElementsFromQueryMatchable(_QueryMatchableExtension matcherBackedObject, PersistentStore store, Map<Type, List<String>> nestedResultProperties) {
    var entity = matcherBackedObject.entity;
    var propertiesToJoin = matcherBackedObject._joinPropertyKeys;

    return propertiesToJoin.map((propertyName) {
      _QueryMatchableExtension inner = matcherBackedObject._matcherMap[propertyName];

      var relDesc = entity.relationships[propertyName];
      var predicate = new Predicate._fromQueryIncludable(inner, store);
      var nestedProperties = nestedResultProperties[inner.entity.instanceType.reflectedType];
      var propertiesToFetch = nestedProperties ?? inner.entity.defaultProperties;

      var joinElements = [
        new JoinMappingElement(JoinType.leftOuter, relDesc, predicate, _mappingElementsForList(propertiesToFetch, inner.entity))
      ];

      if (inner._hasJoinElements) {
        joinElements.addAll(_joinElementsFromQueryMatchable(inner, store, nestedResultProperties));
      }

      return joinElements;
    }).expand((l) => l).toList();
  }
}

class MappingElement {
  MappingElement(this.property, this.value);
  MappingElement.fromElement(MappingElement original, this.value) {
    property = original.property;
  }

  PropertyDescription property;
  dynamic value;

  String toString() {
    return "MappingElement on $property (Value = $value)";
  }
}


class JoinMappingElement extends MappingElement {
  JoinMappingElement(this.type, PropertyDescription property, this.predicate, this.resultKeys)
      : super(property, null)
  {
    var primaryKeyElement = this.resultKeys.firstWhere((e) {
      var eProp = e.property;
      if (eProp is AttributeDescription) {
        return eProp.isPrimaryKey;
      }
      return false;
    });

    primaryKeyIndex = this.resultKeys.indexOf(primaryKeyElement);
  }

  JoinMappingElement.fromElement(JoinMappingElement original, List<MappingElement> values) : super.fromElement(original, values) {
    type = original.type;
    primaryKeyIndex = original.primaryKeyIndex;
  }

  JoinType type;
  PropertyDescription get joinProperty => (property as RelationshipDescription).inverseRelationship;
  Predicate predicate;
  List<MappingElement> resultKeys;

  int primaryKeyIndex;
  List<MappingElement> get values => value as List<MappingElement>;
}