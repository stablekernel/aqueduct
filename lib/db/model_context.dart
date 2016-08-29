part of aqueduct;

/// Instances are responsible for coordinate with a [DataModel] and [PersistentStore] to execute queries and
/// translate between [Model] objects and a database.
///
/// A [Query] must have a valid [ModelContext] to execute.
class ModelContext {
  /// The default context that all [Query]s run on.
  ///
  /// By default, this will be the first [ModelContext] instantiated in an isolate. Most applications
  /// will not use more than one [ModelContext]. For the purpose of testing, you should set
  /// this value each time you instantiate a [ModelContext] to ensure that a previous test isolate
  /// state does not set this property.
  static ModelContext defaultContext = null;

  /// Creates an instance of [ModelContext] from a [DataModel] and [PersistentStore].
  ///
  /// If this is the first [ModelContext] instantiated on an isolate, this instance will because the [defaultContext].
  ModelContext(this.dataModel, this.persistentStore) {
    if (defaultContext == null) {
      defaultContext = this;
    }
  }

  /// The persistent store that [Query]s on this context are executed on.
  PersistentStore persistentStore;

  /// The data model containing the [ModelEntity]s for all types that are managed by this context.
  DataModel dataModel;

  ModelEntity entityForType(Type type) {
    return dataModel.entityForType(type);
  }

  Future<Model> _executeInsertQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeInsertQuery(psq);

    return entity.instanceFromMappingElements(results);
  }

  Future<List<Model>> _executeFetchQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeFetchQuery(psq);

    return _coalesceAndMapRows(results, entity);
  }

  Future<List<Model>> _executeUpdateQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, persistentStore, query);
    var results = await persistentStore.executeUpdateQuery(psq);

    return results.map((row) {
      return entity.instanceFromMappingElements(row);
    }).toList();
  }

  Future<int> _executeDeleteQuery(Query query) async {
    return await persistentStore.executeDeleteQuery(new PersistentStoreQuery(dataModel.entityForType(query.modelType), persistentStore, query));
  }

  List<Model> _coalesceAndMapRows(List<List<MappingElement>> elements, ModelEntity entity) {
    if (elements.length == 0) {
      return [];
    }

    // If we don't have any JoinElements, we should avoid doing anything special.
    if (!elements.first.any((e) => e is JoinMappingElement)) {
      return elements.map((row) {
        return entity.instanceFromMappingElements(row);
      }).toList();
    }

    // There needs to be tests to ensure that the order of JoinElements is dependent.
    List<JoinMappingElement> joinElements = elements.first
        .where((e) => e is JoinMappingElement)
        .toList();

    var joinElementIndexes = joinElements
        .map((e) => elements.first.indexOf(e))
        .toList();

    var primaryKeyColumn = elements.first.firstWhere((e) {
      var eProp = e.property;
      if (eProp is AttributeDescription) {
        return eProp.isPrimaryKey;
      }
      return false;
    });

    var primaryKeyColumnIndex = elements.first.indexOf(primaryKeyColumn);
    Map<String, Map<dynamic, Model>> matchMap = {};

    var primaryTypeString = entity.tableName;
    matchMap[primaryTypeString] = {};
    joinElements
        .map((JoinMappingElement e) => e.joinProperty.entity.tableName)
        .forEach((name) {
          matchMap[name] = {};
        });

    elements.forEach((row) {
      var primaryTypeInstance = _createInstanceIfNecessary(entity, row, primaryKeyColumnIndex, joinElements, matchMap).first;
      Map<ModelEntity, Model> instancesInThisRow = {entity : primaryTypeInstance};

      joinElementIndexes
          .map((joinIndex) => row[joinIndex])
          .forEach((MappingElement element) {
            JoinMappingElement joinElement = element;

            var subInstanceTuple = _createInstanceIfNecessary(joinElement.joinProperty.entity, joinElement.values, joinElement.primaryKeyIndex, joinElements, matchMap);
            if (subInstanceTuple == null) {
              return;
            }

            Model subInstance = subInstanceTuple.first;
            instancesInThisRow[joinElement.joinProperty.entity] = subInstance;
            if (subInstanceTuple.last) {
              RelationshipDescription owningModelPropertyDesc = joinElement.property;
              Model owningInstance = instancesInThisRow[owningModelPropertyDesc.entity];

              var inversePropertyName = owningModelPropertyDesc.name;
              if (owningModelPropertyDesc.relationshipType == RelationshipType.hasMany) {
                owningInstance[inversePropertyName].add(subInstance);
              } else {
                owningInstance[inversePropertyName] = subInstance;
              }
            }
          });
    });

    return matchMap[primaryTypeString].values.toList();
  }

  // Returns a two element tuple, where the first element is the instance represented by mapping the columns across the mappingEntity. The second
  // element is a boolean indicating if the instance was newly created (true) or already existed in the result set (false).
  List<dynamic> _createInstanceIfNecessary(ModelEntity mappingEntity, List<MappingElement> columns, int primaryKeyIndex, List<JoinMappingElement> joinElements, Map<String, Map<dynamic, Model>> matchMap) {
    var primaryKeyValue = columns[primaryKeyIndex].value;
    if (primaryKeyValue == null) {
      return null;
    }

    var existingInstance = matchMap[mappingEntity.tableName][primaryKeyValue];

    var isNewInstance = false;
    if (existingInstance == null) {
      isNewInstance = true;

      existingInstance = mappingEntity.instanceFromMappingElements(columns);
      joinElements
          .where((je) => je.property.entity == mappingEntity)
          .forEach((je) {
            RelationshipDescription relDesc = je.property;

            if (relDesc.relationshipType == RelationshipType.hasMany) {
              existingInstance[je.property.name] = [];
            } else {
              existingInstance[je.property.name] = null;
            }
          });

      matchMap[mappingEntity.tableName][primaryKeyValue] = existingInstance;
    }
    return [existingInstance, isNewInstance];
  }
}

