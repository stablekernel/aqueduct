part of aqueduct;

class SchemaBuilder {
  SchemaBuilder.toSchema(this.store, Schema targetSchema, {this.isTemporary: false}) {
    schema = new Schema.empty();
    targetSchema.dependencyOrderedTables.forEach((t) {
      _createTable(t);
    });
  }

  SchemaBuilder(this.store, this._currentSchema, {this.isTemporary: false}) {
    schema = new Schema.from(_currentSchema);
  }

  Schema _currentSchema;
  Schema schema;
  PersistentStore store;
  bool isTemporary;
  List<String> commands = [];

  Future execute() async {
    // Wrap in transaction
    for (var cmd in commands) {
      await store.execute(cmd);
    }
  }

  void _createTable(SchemaTable table) {
    if (schema.tableForName(table.name) != null) {
      throw new SchemaException("Table ${table.name} already exist.");
    }

    schema.addTable(table);
    commands.addAll(store.createTable(table, isTemporary: isTemporary));
  }

  void createTable(void create(SchemaTable table)) {
    var table = new SchemaTable.empty();
    create(table);

    _createTable(table);
  }

  void renameTable(String currentTableName, String newName) {
    var table = schema.tableForName(currentTableName);
    if (table == null) {
      throw new SchemaException("Table ${newName} does not exist.");
    }

    if (schema.tableForName(newName) != null) {
      throw new SchemaException("Table ${newName} already exist.");
    }

    schema.renameTable(table, newName);
    commands.addAll(store.renameTable(table, newName));
  }

  void deleteTable(String tableName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    schema.removeTable(table);
    commands.addAll(store.deleteTable(table));
  }

  void addColumn(String tableName, void create(SchemaColumn column)) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    var column = new SchemaColumn.empty();
    create(column);
    if (table.columnForName(column.name) != null) {
      throw new SchemaException("Column ${column.name} already exists.");
    }

    table.addColumn(column);
    commands.addAll(store.addColumn(table, column));
  }

  void deleteColumn(String tableName, String columnName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${table.name} does not exist.");
    }

    var column = table.columnForName(columnName);
    if (column == null) {
      throw new SchemaException("Column ${columnName} does not exists.");
    }

    table.removeColumn(column);

    commands.addAll(store.deleteColumn(table, column));
  }

  void renameColumn(String tableName, String columnName, String newName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    var column = table.columnForName(columnName);
    if (column == null) {
      throw new SchemaException("Column ${columnName} does not exists.");
    }

    if (table.columnForName(newName) != null) {
      throw new SchemaException("Column ${newName} already exists.");
    }

    if (column.isPrimaryKey) {
      throw new SchemaException("May not rename primary key column (${column.name} -> ${newName})");
    }

    table.renameColumn(column, newName);
    commands.addAll(store.renameColumn(table, column, newName));
  }

  void alterColumn(String tableName, String columnName, void modify(SchemaColumn targetColumn), {String unencodedInitialValue}) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    var existingColumn = table[columnName];
    if (existingColumn != null) {
      throw new SchemaException("Column ${columnName} does not exist.");
    }

    var newColumn = new SchemaColumn.from(existingColumn);
    modify(newColumn);

    // TODO: change delete rule at same time nullability is changed hsould be ok
    if (existingColumn.type != newColumn.type) {
      throw new SchemaException("May not change column (${existingColumn.name}) type (${existingColumn.type} -> ${newColumn.type})");
    }

    if (existingColumn.autoincrement != newColumn.autoincrement) {
      throw new SchemaException("May not change column (${existingColumn.name}) autoincrementing behavior");
    }

    if (existingColumn.isPrimaryKey != newColumn.isPrimaryKey) {
      throw new SchemaException("May not change column (${existingColumn.name}) to/from primary key");
    }

    if(existingColumn.relatedTableName != newColumn.relatedTableName) {
      throw new SchemaException("May not change column (${existingColumn.name}) reference table (${existingColumn.relatedTableName} -> ${newColumn.relatedTableName})");
    }

    if(existingColumn.relatedColumnName != newColumn.relatedColumnName) {
      throw new SchemaException("May not change column (${existingColumn.name}) reference column (${existingColumn.relatedColumnName} -> ${newColumn.relatedColumnName})");
    }

    if (existingColumn.name != newColumn.name) {
      renameColumn(tableName, existingColumn.name, newColumn.name);
    }

    table.replaceColumn(existingColumn, newColumn);

    if (existingColumn.isIndexed != newColumn.isIndexed) {
      if (newColumn.isIndexed) {
        commands.addAll(store.addIndexToColumn(table, newColumn));
      } else {
        commands.addAll(store.deleteIndexFromColumn(table, newColumn));
      }
    }

    if (existingColumn.isNullable != newColumn.isNullable) {
      commands.addAll(store.alterColumnNullability(table, newColumn, unencodedInitialValue));
    }

    if (existingColumn.isUnique != newColumn.isUnique) {
      commands.addAll(store.alterColumnUniqueness(table, newColumn));
    }

    if (existingColumn.defaultValue != newColumn.defaultValue) {
      commands.addAll(store.alterColumnDefaultValue(table, newColumn));
    }

    if (existingColumn.deleteRule != newColumn.deleteRule) {
      commands.addAll(store.alterColumnDeleteRule(table, newColumn));
    }
  }
}