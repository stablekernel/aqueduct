part of aqueduct;

class SchemaBuilder {
  SchemaBuilder(this.store, this.currentSchema, this.targetSchema, {this.isTemporary: false}) {
    if (this.currentSchema.tables.isEmpty) {
      _builtSchema = new Schema.empty();
      targetSchema.dependencyOrderedTables.forEach((t) {
        createTable(t);
      });
    } else {
      _builtSchema = new Schema.from(currentSchema);
    }
  }

  Schema currentSchema;
  Schema targetSchema;
  Schema _builtSchema;
  PersistentStore store;
  bool isTemporary;
  List<String> commands = [];

  void createTable(SchemaTable table) {
    _builtSchema.addTable(table);

    commands.addAll(store.createTable(table, isTemporary: isTemporary));
  }
}