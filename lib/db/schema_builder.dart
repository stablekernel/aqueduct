part of aqueduct;

class SchemaBuilder {
  SchemaBuilder(this.store, this.inputSchema, {this.isTemporary: false}) {
    schema = new Schema.from(inputSchema);
  }

  SchemaBuilder.toSchema(this.store, Schema targetSchema, {this.isTemporary: false}) {
    schema = new Schema.empty();
    targetSchema.dependencyOrderedTables.forEach((t) {
      createTable(t);
    });
  }

  Schema inputSchema;
  Schema schema;
  PersistentStore store;
  bool isTemporary;
  List<String> commands = [];

  Future execute(int versionNumber) async {
    // Wrap in transaction
    for (var cmd in commands) {
      await store.execute(cmd);
    }
    await store.updateVersionNumber(versionNumber);
  }

  void createTable(SchemaTable table) {
    schema.addTable(table);

    if (store != null) {
      commands.addAll(store.createTable(table, isTemporary: isTemporary));
    }
  }

  void renameTable(String currentTableName, String newName) {
    var table = schema.tableForName(currentTableName);
    if (table == null) {
      throw new SchemaException("Table ${currentTableName} does not exist.");
    }

    schema.renameTable(table, newName);
    if (store != null) {
      commands.addAll(store.renameTable(table, newName));
    }
  }

  void deleteTable(String tableName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    schema.removeTable(table);

    if (store != null) {
      commands.addAll(store.deleteTable(table));
    }
  }

  void addColumn(String tableName, SchemaColumn column) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    table.addColumn(column);
    if (store != null) {
      commands.addAll(store.addColumn(table, column));
    }
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

    if (store != null) {
      commands.addAll(store.deleteColumn(table, column));
    }
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

    table.renameColumn(column, newName);

    if (store != null) {
      commands.addAll(store.renameColumn(table, column, newName));
    }
  }

  void alterColumn(String tableName, String columnName, void modify(SchemaColumn targetColumn), {String unencodedInitialValue}) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw new SchemaException("Table ${tableName} does not exist.");
    }

    var existingColumn = table[columnName];
    if (existingColumn == null) {
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

    table._replaceColumn(existingColumn, newColumn);

    if (store != null) {
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

  static String sourceForSchemaUpgrade(Schema existingSchema, Schema newSchema, int version) {
    var builder = new StringBuffer();
    builder.writeln("import 'package:aqueduct/aqueduct.dart';");
    builder.writeln("");
    builder.writeln("class Migration$version extends Migration {");
    builder.writeln("  Future upgrade() async {");

    var existingTableNames = existingSchema.tables.map((t) => t.name).toList();
    var newTableNames = newSchema.tables.map((t) => t.name).toList();

    newSchema.tables
        .where((t) => !existingTableNames.contains(t.name))
        .forEach((t) {
          builder.writeln(_createTableString(t, "    "));
        });

    builder.writeln("  }");
    builder.writeln("");
    builder.writeln("  Future downgrade() async {");
    builder.writeln("  }");
    builder.writeln("  Future seed() async {");
    builder.writeln("  }");
    builder.writeln("}");

    return builder.toString();
  }

  static String _createTableString(SchemaTable table, String spaceOffset, {bool temporary: false}) {
    var builder = new StringBuffer();
    builder.writeln('${spaceOffset}database.createTable(new SchemaTable("${table.name}", [');
    table.columns.forEach((col) {
      builder.writeln("${spaceOffset}${_newColumnString(table, col, "  ")},");
    });
    builder.writeln('${spaceOffset}]));');

    return builder.toString();
  }

  static String _newColumnString(SchemaTable table, SchemaColumn column, String spaceOffset) {
    var builder = new StringBuffer();
    builder.write('${spaceOffset}new SchemaColumn("${column.name}", ${SchemaColumn.typeFromTypeString(column.type)}');
    if (column.isPrimaryKey) {
      builder.write(", isPrimaryKey: true");
    } else {
      builder.write(", isPrimaryKey: false");
    }
    if (column.isIndexed) {
      builder.write(", isIndexed: true");
    } else {
      builder.write(", isIndexed: false");
    }
    if (column.isNullable) {
      builder.write(", isNullable: true");
    } else {
      builder.write(", isNullable: false");
    }
    if (column.isUnique) {
      builder.write(", isUnique: true");
    } else {
      builder.write(", isUnique: false");
    }
    if (column.autoincrement) {
      builder.write(", autoincrement: true");
    } else {
      builder.write(", autoincrement: false");
    }
    if (column.defaultValue != null) {
      builder.write(', defaultValue: "${column.defaultValue}"');
    }

    builder.write(")");
    return builder.toString();
  }
}