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
    var psq = new PersistentStoreQuery(entity, query);
    var results = await persistentStore.executeInsertQuery(psq);

    return psq.createInstanceFromMappingElements(results);
  }

  Future<List<Model>> executeFetchQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, query);
    var results = await persistentStore.executeFetchQuery(psq);

    return results.map((row) {
      return psq.createInstanceFromMappingElements(row);
    }).toList();
  }

  Future<List<Model>> executeUpdateQuery(Query query) async {
    var entity = dataModel.entityForType(query.modelType);
    var psq = new PersistentStoreQuery(entity, query);
    var results = await persistentStore.executeUpdateQuery(psq);

    return results.map((row) {
      return psq.createInstanceFromMappingElements(row);
    }).toList();
  }

  Future<int> executeDeleteQuery(Query query) async {
    return await persistentStore.executeDeleteQuery(new PersistentStoreQuery(dataModel.entityForType(query.modelType), query));
  }

  Future<int> executeCountQuery(Query query) async {
    var results = await persistentStore.executeCountQuery(new PersistentStoreQuery(dataModel.entityForType(query.modelType), query));
    return results;
  }
}
