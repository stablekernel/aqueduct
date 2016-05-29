part of aqueduct;

class PersistentStoreQuery {
  PersistentStoreQuery(this.entity, PersistentStore store, Query q) {
    if (q is ModelQuery && q.subQueries.length > 0) {
      _instantiateFromMultiJoinQuery(store, q);
    } else {
      _instantiateFromSingleQuery(store, q);
    }
  }

  ModelEntity entity;
  int timeoutInSeconds = 30;
  int fetchLimit = 0;
  int offset = 0;
  QueryPage pageDescriptor;
  List<SortDescriptor> sortDescriptors;
  Predicate predicate;
  JoinMappingElement joinInfo;
  List<MappingElement> values;
  List<MappingElement> resultKeys;

  void _instantiateFromMultiJoinQuery(PersistentStore store, ModelQuery q) {
    // This only gets called if we DO have subqueries, so assume that.

    // Ignore fetchLimit, offset, pageDescriptor - do we throw an exception or just run them in software?

    timeoutInSeconds = q.timeoutInSeconds;
    sortDescriptors = q.sortDescriptors;

    predicate = q._compilePredicate(entity.dataModel, store);
    resultKeys = _mappingElementsForList((q.resultKeys ?? entity.defaultProperties), entity);

    resultKeys.addAll(q.subQueries.keys
        .map((subqueryKey) => _joinsForQuery(store, q, subqueryKey))
        .expand((l) => l)
    );
  }

  void _instantiateFromSingleQuery(PersistentStore store, Query q) {
    timeoutInSeconds = q.timeoutInSeconds;
    fetchLimit = q.fetchLimit;
    offset = q.offset;
    pageDescriptor = q.pageDescriptor;
    sortDescriptors = q.sortDescriptors;

    q._compilePredicate(entity.dataModel, store);
    predicate = q._compilePredicate(entity.dataModel, store);

    if (q.valueObject != null && q.values != null) {
      throw new QueryException(500, "Query has both values and valueObject set", -1);
    }

    values = _mappingElementsForMap((q.values ?? q.valueObject?.dynamicBacking), this.entity);
    resultKeys = _mappingElementsForList((q.resultKeys ?? entity.defaultProperties), this.entity);
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
            value = value.dynamicBacking[property.destinationEntity.primaryKey];
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

  static List<JoinMappingElement> _joinsForQuery(PersistentStore store, ModelQuery query, String subQueryKey) {
    var relationship = query.entity.relationships[subQueryKey];
    var destinationEntity = relationship.destinationEntity;
    var subQuery = query.subQueries[subQueryKey];

    var mappingElements = _mappingElementsForList(subQuery.resultKeys ?? destinationEntity.defaultProperties, destinationEntity);
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
    primaryKeyIndex = this.resultKeys.indexOf(this.resultKeys.firstWhere((e) => e.property is AttributeDescription && e.property.isPrimaryKey));
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
  List<MappingElement> get values => value;
}