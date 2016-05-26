part of aqueduct;

class ModelContext {
  static ModelContext defaultContext = null;

  ModelContext(this.dataModel, this.persistentStore) {
    if (defaultContext == null) {
      defaultContext = this;
    }
  }

  PersistentStore persistentStore;
  DataModel dataModel;

  Future<Model> executeInsertQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeInsertQuery(psq);

    return entity.instanceFromMappingElements(results);
  }

  Future<List<Model>> executeFetchQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeFetchQuery(psq);

    return _coalesceAndMapRows(results, entity);
  }

  Future<List<Model>> executeUpdateQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeUpdateQuery(psq);

    return results.map((row) {
      return entity.instanceFromMappingElements(row);
    }).toList();
  }

  Future<int> executeDeleteQuery(Query query) async {
    return await persistentStore.executeDeleteQuery(new PersistentStoreQuery(dataModel.entityForType(query.modelType), persistentStore, query));
  }

  Future<int> executeCountQuery(Query query) async {
    var results = await persistentStore.executeCountQuery(new PersistentStoreQuery(dataModel.entityForType(query.modelType), persistentStore, query));
    return results;
  }

  List<Model> _coalesceAndMapRows(List<List<MappingElement>> elements, ModelEntity entity) {
    if (elements.length == 0) {
      return [];
    }

    // If we don't have any JoinElements, we should avoid doing anything special.
    if (!elements.first.any((e) => e is JoinElement)) {
      return elements.map((row) {
        return entity.instanceFromMappingElements(row);
      }).toList();
    }

    // Need to order these by dependents, which I think we can do prior to them going into the grinder
    var joinElements = elements.first
        .where((e) => e is JoinElement)
        .toList();

    var joinElementIndexes = joinElements
        .map((e) => elements.first.indexOf(e))
        .toList();

    var primaryKeyColumn = elements.first.firstWhere((e) => e.property is AttributeDescription && e.property.isPrimaryKey);
    var primaryKeyColumnIndex = elements.first.indexOf(primaryKeyColumn);
    Map<String, Map<dynamic, Model>> matchMap = {};

    var primaryTypeString = entity.tableName;
    matchMap[primaryTypeString] = {};
    joinElements
        .map((JoinElement e) => e.joinProperty.entity.tableName)
        .forEach((name) {
          matchMap[name] = {};
        });


    elements.forEach((row) {
      // Fnd a better way to set lists to empty on instantiation of instance, if a join does exist..
      var primaryTypeInstance = _createInstanceIfNecessary(entity, row, primaryKeyColumnIndex, joinElements, matchMap).first;
      Map<ModelEntity, Model> instancesInThisRow = {entity : primaryTypeInstance};

      joinElementIndexes
          .map((joinIndex) => row[joinIndex])
          .forEach((JoinElement joinElement) {
            var subInstanceTuple = _createInstanceIfNecessary(joinElement.joinProperty.entity, joinElement.values, joinElement.primaryKeyIndex, joinElements, matchMap);
            if (subInstanceTuple == null) {
              return;
            }

            Model subInstance = subInstanceTuple.first;
            instancesInThisRow[joinElement.joinProperty.entity] = subInstance;
            if (subInstanceTuple.last) {
              // This is a new element, associate it. Find the matching instance from THIS row and sets it dynamic backing for the inversePropertyName.

              RelationshipDescription owningModelPropertyDesc = joinElement.property;
              Model owningInstance = instancesInThisRow[owningModelPropertyDesc.entity];

              var inversePropertyName = owningModelPropertyDesc.name;
              if (owningModelPropertyDesc.relationshipType == RelationshipType.hasMany) {
                owningInstance.dynamicBacking[inversePropertyName].add(subInstance);
              } else {
                owningInstance.dynamicBacking[inversePropertyName] = subInstance;
              }
            }
          });
    });

    return matchMap[primaryTypeString].values.toList();
  }

  List<dynamic> _createInstanceIfNecessary(ModelEntity mappingEntity, List<MappingElement> columns, int primaryKeyIndex, List<JoinElement> joinElements, Map<String, Map<dynamic, Model>> matchMap) {
    var primaryKeyValue = columns[primaryKeyIndex].value;
    if (primaryKeyValue == null) {
      return null;
    }

    var primaryTypeInstance = matchMap[mappingEntity.tableName][primaryKeyValue];

    var isNewInstance = false;
    if (primaryTypeInstance == null) {
      isNewInstance = true;
      primaryTypeInstance = mappingEntity.instanceFromMappingElements(columns);
      joinElements
          .where((je) => je.property.entity == mappingEntity && je.property.relationshipType == RelationshipType.hasMany)
          .forEach((je) {
            primaryTypeInstance[je.property.name] = [];
      });
      matchMap[mappingEntity.tableName][primaryKeyValue] = primaryTypeInstance;

    }
    return [primaryTypeInstance, isNewInstance];
  }

}

