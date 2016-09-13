part of aqueduct;

class PersistentStoreQuery {
  PersistentStoreQuery(this.rootEntity, PersistentStore store, Query q) {
    confirmQueryModifiesAllInstancesOnDeleteOrUpdate = q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
    timeoutInSeconds = q.timeoutInSeconds;
    sortDescriptors = q.sortDescriptors;
    resultKeys = _mappingElementsForList((q.resultProperties ?? rootEntity.defaultProperties), rootEntity);

    if (q._matchOn != null) {
      predicate = new Predicate._fromMatcherBackedObject(q._matchOn, store);
    } else {
      predicate = q.predicate;
    }

    if (q._include != null) {
      var joinElements = _joinElementsForMatcherBackedObject(q._include, store, q.nestedResultProperties);
      resultKeys.addAll(joinElements);
    } else {
      fetchLimit = q.fetchLimit;
      offset = q.offset;
      pageDescriptor = q.pageDescriptor;

      values = _mappingElementsForMap((q.valueMap ?? q.values?.populatedPropertyValues), rootEntity);
    }
  }

  ModelEntity rootEntity;
  int timeoutInSeconds = 30;
  int fetchLimit = 0;
  int offset = 0;
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
  QueryPage pageDescriptor;
  List<SortDescriptor> sortDescriptors;
  Predicate predicate;
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
            throw new QueryException(500, "Property $key on ${entity.tableName} in Query values must be a Map or ${MirrorSystem.getName(property.destinationEntity.instanceTypeMirror.simpleName)} ", -1);
          }
        }
      }

      return new MappingElement(property, value);
    })
    ?.where((m) => m != null)
    ?.toList();
  }

  static List<JoinMappingElement> _joinElementsForMatcherBackedObject(Model matcherBackedObject, PersistentStore store, Map<Type, List<String>> nestedResultProperties) {
    var entity = matcherBackedObject.entity;
    var relationshipKeys = matcherBackedObject.populatedPropertyValues.keys.where((propertyName) {
      var matcherRelationship = entity.relationships[propertyName];
      if (matcherRelationship == null) {
        return false;
      }

      return matcherRelationship.relationshipType == RelationshipType.hasMany
          || matcherRelationship.relationshipType == RelationshipType.hasOne;
    }).toList();

    return relationshipKeys.map((propertyName) {
      var matcher = matcherBackedObject.populatedPropertyValues[propertyName];

      var relDesc = entity.relationships[propertyName];
      var predicate = null;
      if (matcher._matchOn != null) {
        predicate = new Predicate._fromMatcherBackedObject(matcher.matchOn, store);
      }

      var nestedProperties = nestedResultProperties[matcher.entity.instanceTypeMirror.reflectedType];
      var propertiesToFetch = nestedProperties ?? matcher.entity.defaultProperties;
      // Using default props
      var joinElements = [new JoinMappingElement(JoinType.leftOuter,
          relDesc,
          predicate,
          _mappingElementsForList(propertiesToFetch, matcher.entity))];

      if (matcher._include != null) {
        joinElements.addAll(_joinElementsForMatcherBackedObject(matcher._include, store, nestedResultProperties));
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

enum JoinType {
  leftOuter
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