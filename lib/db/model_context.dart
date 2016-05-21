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
}