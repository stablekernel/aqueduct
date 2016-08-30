part of aqueduct;

class PersistentStoreQuery {
  PersistentStoreQuery(this.entity, PersistentStore store, Query q) {
    if (q._include != null) {
      _instantiateFromMultiJoinQuery(store, q);
    } else {
      _instantiateFromSingleQuery(store, q);
    }
  }

  ModelEntity entity;
  int timeoutInSeconds = 30;
  int fetchLimit = 0;
  int offset = 0;
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
  QueryPage pageDescriptor;
  List<SortDescriptor> sortDescriptors;
  Predicate predicate;
  JoinMappingElement joinInfo;
  List<MappingElement> values;
  List<MappingElement> resultKeys;

  void _instantiateFromMultiJoinQuery(PersistentStore store, Query q) {
    confirmQueryModifiesAllInstancesOnDeleteOrUpdate = q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
    // This only gets called if we DO have subqueries, so assume that.

    // Ignore fetchLimit, offset, pageDescriptor - do we throw an exception or just run them in software?

    timeoutInSeconds = q.timeoutInSeconds;
    sortDescriptors = q.sortDescriptors;

    predicate = q._compilePredicate(entity.dataModel, store);
    resultKeys = _mappingElementsForList((q.resultProperties ?? entity.defaultProperties), entity);

    resultKeys.addAll(q.subQueries.keys
        .map((subqueryKey) => _joinsForQuery(store, q, subqueryKey))
        .expand((l) => l)
    );
  }

  void _instantiateFromSingleQuery(PersistentStore store, Query q) {
    confirmQueryModifiesAllInstancesOnDeleteOrUpdate = q.confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
    timeoutInSeconds = q.timeoutInSeconds;
    fetchLimit = q.fetchLimit;
    offset = q.offset;
    pageDescriptor = q.pageDescriptor;
    sortDescriptors = q.sortDescriptors;

    predicate = q._compilePredicate(entity.dataModel, store);

    values = _mappingElementsForMap((q.valueMap ?? q.values?.populatedPropertyValues), this.entity);
    resultKeys = _mappingElementsForList((q.resultProperties ?? entity.defaultProperties), this.entity);
  }

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

  static List<JoinMappingElement> _joinsForQuery(PersistentStore store, Query query, String subQueryKey) {
    var relationship = query.entity.relationships[subQueryKey];
    var destinationEntity = relationship.destinationEntity;
    var subQuery = query.subQueries[subQueryKey];

    var mappingElements = _mappingElementsForList(subQuery.resultProperties ?? destinationEntity.defaultProperties, destinationEntity);
    var thisJoin = new JoinMappingElement(JoinType.leftOuter, relationship, subQuery._compilePredicate(query.entity.dataModel, store), mappingElements);

    var subSubQueryJoins = subQuery.subQueries.keys.map((innerSubqueryKey) {
      return _joinsForQuery(store, subQuery, innerSubqueryKey);
    }).expand((l) => l).toList();

    var ordered = [thisJoin];
    ordered.addAll(subSubQueryJoins);
    return ordered;
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
  JoinMappingElement(this.type, PropertyDescription property, this.predicate, this.resultKeys) : super(property, null) {
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