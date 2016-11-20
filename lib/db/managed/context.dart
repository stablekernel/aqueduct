part of aqueduct;

/// Coordinates with a [ManagedDataModel] and [PersistentStore] to execute queries and
/// translate between [ManagedObject] objects and database rows.
///
/// An application that uses Aqueduct's ORM functionality must create an instance of this type.
///
/// A [Query] must have a valid [ManagedContext] to execute. Most applications only need one [ManagedContext],
/// so the first [ManagedContext] instantiated becomes the [ManagedContext.defaultContext]. By default, [Query]s
/// target the [ManagedContext.defaultContext].
class ManagedContext {
  /// The default context that a [Query] runs on.
  ///
  /// For classes that require a [ManagedContext] - like [Query] - this is the default context when none
  /// is specified.
  ///
  /// This value is set when the first [ManagedContext] instantiated in an isolate. Most applications
  /// will not use more than one [ManagedContext]. When running tests, you should set
  /// this value each time you instantiate a [ManagedContext] to ensure that a previous test isolate
  /// state did not set this property.
  static ManagedContext defaultContext = null;

  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// If this is the first [ManagedContext] instantiated on an isolate, this instance will because the [ManagedContext.defaultContext].
  ManagedContext(this.dataModel, this.persistentStore) {
    if (defaultContext == null) {
      defaultContext = this;
    }
  }

  /// The persistent store that [Query]s on this context are executed on.
  PersistentStore persistentStore;

  /// The data model containing the [ManagedEntity]s that describe the [ManagedObject]s this instance works with.
  ManagedDataModel dataModel;

  /// Returns an entity for a type from [dataModel].
  ///
  /// See [ManagedDataModel.entityForType].
  ManagedEntity entityForType(Type type) {
    return dataModel.entityForType(type);
  }

  Future<ManagedObject> _executeInsertQuery(Query query) async {
    var psq = new PersistentStoreQuery(query.entity, persistentStore, query);
    var results = await persistentStore.executeInsertQuery(psq);

    return query.entity.instanceFromMappingElements(results);
  }

  Future<List<ManagedObject>> _executeFetchQuery(Query query) async {
    var psq = new PersistentStoreQuery(query.entity, persistentStore, query);
    var results = await persistentStore.executeFetchQuery(psq);

    return _coalesceAndMapRows(results, query.entity);
  }

  Future<List<ManagedObject>> _executeUpdateQuery(Query query) async {
    var psq = new PersistentStoreQuery(query.entity, persistentStore, query);
    var results = await persistentStore.executeUpdateQuery(psq);

    return results.map((row) {
      return query.entity.instanceFromMappingElements(row);
    }).toList();
  }

  Future<int> _executeDeleteQuery(Query query) async {
    return await persistentStore.executeDeleteQuery(
        new PersistentStoreQuery(query.entity, persistentStore, query));
  }

  List<ManagedObject> _coalesceAndMapRows(
      List<List<PersistentColumnMapping>> elements, ManagedEntity entity) {
    if (elements.length == 0) {
      return [];
    }

    // If we don't have any JoinElements, we should avoid doing anything special.
    if (!elements.first.any((e) => e is PersistentJoinMapping)) {
      return elements.map((row) {
        return entity.instanceFromMappingElements(row);
      }).toList();
    }

    // There needs to be tests to ensure that the order of JoinElements is dependent.
    List<PersistentJoinMapping> joinElements =
        elements.first.where((e) => e is PersistentJoinMapping).toList();

    var joinElementIndexes =
        joinElements.map((e) => elements.first.indexOf(e)).toList();

    var primaryKeyColumn = elements.first.firstWhere((e) {
      var eProp = e.property;
      if (eProp is ManagedAttributeDescription) {
        return eProp.isPrimaryKey;
      }
      return false;
    });

    var primaryKeyColumnIndex = elements.first.indexOf(primaryKeyColumn);
    Map<String, Map<dynamic, ManagedObject>> matchMap = {};

    var primaryTypeString = entity.tableName;
    matchMap[primaryTypeString] = {};
    joinElements
        .map((PersistentJoinMapping e) => e.joinProperty.entity.tableName)
        .forEach((name) {
      matchMap[name] = {};
    });

    elements.forEach((row) {
      var primaryTypeInstance = _createInstanceIfNecessary(
              entity, row, primaryKeyColumnIndex, joinElements, matchMap)
          .first as ManagedObject;
      Map<ManagedEntity, ManagedObject> instancesInThisRow = {
        entity: primaryTypeInstance
      };

      joinElementIndexes
          .map((joinIndex) => row[joinIndex])
          .forEach((PersistentColumnMapping element) {
        PersistentJoinMapping joinElement = element;

        var subInstanceTuple = _createInstanceIfNecessary(
            joinElement.joinProperty.entity,
            joinElement.values,
            joinElement.primaryKeyIndex,
            joinElements,
            matchMap);
        if (subInstanceTuple == null) {
          return;
        }

        ManagedObject subInstance = subInstanceTuple.first;
        instancesInThisRow[joinElement.joinProperty.entity] = subInstance;
        if (subInstanceTuple.last) {
          ManagedRelationshipDescription owningModelPropertyDesc =
              joinElement.property;
          ManagedObject owningInstance =
              instancesInThisRow[owningModelPropertyDesc.entity];

          var inversePropertyName = owningModelPropertyDesc.name;
          if (owningModelPropertyDesc.relationshipType ==
              ManagedRelationshipType.hasMany) {
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
  List<dynamic> _createInstanceIfNecessary(
      ManagedEntity mappingEntity,
      List<PersistentColumnMapping> columns,
      int primaryKeyIndex,
      List<PersistentJoinMapping> joinElements,
      Map<String, Map<dynamic, ManagedObject>> matchMap) {
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
        ManagedRelationshipDescription relDesc = je.property;

        if (relDesc.relationshipType == ManagedRelationshipType.hasMany) {
          existingInstance[je.property.name] = new ManagedSet();
        } else {
          existingInstance[je.property.name] = null;
        }
      });

      matchMap[mappingEntity.tableName][primaryKeyValue] = existingInstance;
    }
    return [existingInstance, isNewInstance];
  }
}
