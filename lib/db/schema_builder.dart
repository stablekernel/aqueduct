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

  Future _executeCommands() async {
    // Wrap in transaction
    for (var cmd in commands) {
      await store.execute(cmd);
    }
  }

  void createTable(SchemaTable table) {
    _builtSchema.addTable(table);

    commands.addAll(store.createTable(table, isTemporary: isTemporary));
  }

  // alter table, if setting to not null, must include initialValue
  // alter table, change delete rule, must be verified - already verified by DataModel
}