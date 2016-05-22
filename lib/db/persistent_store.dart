part of aqueduct;

abstract class PersistentStore {
  Future execute(String sql);
  /// Closes the underlying database connection.
  Future close();

  Future<List<MappingElement>> executeInsertQuery(PersistentStoreQuery q);
  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q);
  Future<int> executeDeleteQuery(PersistentStoreQuery q);
  Future<List<List<MappingElement>>> executeUpdateQuery(PersistentStoreQuery q);
  Future<int> executeCountQuery(PersistentStoreQuery q);

  String foreignKeyForRelationshipDescription(RelationshipDescription desc) {
    return "${desc.name}_${desc.destinationEntity.primaryKey}";
  }

}

class DefaultPersistentStore extends PersistentStore {
  Future<dynamic> execute(String sql) async { return null; }
  Future close() async {}
  Future<List<MappingElement>> executeInsertQuery(PersistentStoreQuery q) async { return null; }
  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q) async { return null; }
  Future<int> executeDeleteQuery(PersistentStoreQuery q) async { return null; }
  Future<List<List<MappingElement>>> executeUpdateQuery(PersistentStoreQuery q) async { return null; }
  Future<int> executeCountQuery(PersistentStoreQuery q) async { return null; }
}

class MappingElement {
  PropertyDescription property;
  dynamic value;
}

class PersistentStoreQuery {
  PersistentStoreQuery(this.entity, Query q) {
    timeoutInSeconds = q.timeoutInSeconds;
    fetchLimit = q.fetchLimit;
    offset = q.offset;
    pageDescriptor = q.pageDescriptor;
    sortDescriptors = q.sortDescriptors;
    predicate = q.predicate;

    if (q.valueObject != null && q.values != null) {
      throw new QueryException(500, "Query has both values and valueObject set", -1);
    }

    Map<String, dynamic> valueMap = (q.values ?? q.valueObject?.dynamicBacking);
    values = valueMap?.keys
      ?.map((key) {
        var property = entity.properties[key];
        if (property == null) {
          throw new QueryException(400, "Property $key in values does not exist on ${entity.tableName}", -1);
        }

        var value = valueMap[key];
        if (property is RelationshipDescription) {
          if (property.relationshipType != RelationshipType.belongsTo) {
            return null;
          }

          if (value is Model) {
            value = value.dynamicBacking[property.destinationEntity.primaryKey];
          } else if (value is Map) {
            value = value[property.destinationEntity.primaryKey];
          } else {
            throw new QueryException(500, "Property $key on ${entity.tableName} in Query values must be a Map or ${MirrorSystem.getName(property.destinationEntity.instanceTypeMirror.simpleName)} ", -1);
          }
        }

        return new MappingElement()
            ..property = property
            ..value = value;
      })
      ?.where((m) => m != null)
      ?.toList();


    resultKeys = (q.resultKeys ?? entity.defaultProperties).map((key) {
      var property = entity.properties[key];
      if (property == null) {
        throw new QueryException(500, "Property $key in resultKeys does not exist on ${entity.tableName}", -1);
      }
      if (property is RelationshipDescription && property.relationshipType != RelationshipType.belongsTo) {
        throw new QueryException(500, "Property $key in resultKeys is a hasMany or hasOne relationship and is invalid on ${entity.tableName}", -1);
      }

      return new MappingElement()
        ..property = property;
    }).toList();
  }

  ModelEntity entity;
  int timeoutInSeconds;
  int fetchLimit;
  int offset;
  QueryPage pageDescriptor;
  List<SortDescriptor> sortDescriptors;
  Predicate predicate;
  List<MappingElement> values;
  List<MappingElement> resultKeys;

  Model createInstanceFromMappingElements(List<MappingElement> elements) {
    var instance = entity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
    elements.forEach((e) {
      if (e.value == null) {
        return;
      }

      if (e.property is RelationshipDescription) {
        RelationshipDescription relDesc = e.property;
        var innerInstance = relDesc.destinationEntity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
        innerInstance.dynamicBacking[relDesc.destinationEntity.primaryKey] = e.value;
        instance.dynamicBacking[e.property.name] = innerInstance;
      } else {
        instance.dynamicBacking[e.property.name] = e.value;
      }
    });
    return instance;
  }
}