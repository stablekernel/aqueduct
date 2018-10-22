import '../persistent_store/persistent_store.dart';
import 'schema.dart';

/// Used during migration to modify a schema.
class SchemaBuilder {
  /// Creates a builder starting from an existing schema.
  SchemaBuilder(this.store, this.inputSchema, {this.isTemporary = false}) {
    schema = Schema.from(inputSchema);
  }

  /// Creates a builder starting from the empty schema.
  SchemaBuilder.toSchema(this.store, Schema targetSchema,
      {this.isTemporary = false}) {
    schema = Schema.empty();
    targetSchema.tables.forEach((t) {
      final independentTable = SchemaTable.from(t);
      independentTable.columns.where((c) => c.isForeignKey).forEach((c) {
        independentTable.removeColumn(c);
      });
      independentTable.uniqueColumnSet = null;
      createTable(independentTable);
    });

    targetSchema.tables.forEach((t) {
      t.columns.where((c) => c.isForeignKey).forEach((c) {
        addColumn(t.name, c);
      });

      if (t.uniqueColumnSet != null) {
        commands.addAll(store?.addTableUniqueColumnSet(t) ?? []);
      }
    });
  }

  /// The starting schema of this builder.
  Schema inputSchema;

  /// The resulting schema of this builder as operations are applied to it.
  Schema schema;

  /// The persistent store to validate and construct operations.
  PersistentStore store;

  /// Whether or not this builder should create temporary tables.
  bool isTemporary;

  /// A list of SQL commands generated by operations performed on this builder.
  List<String> commands = [];

  /// Validates and adds a table to [schema].
  void createTable(SchemaTable table) {
    schema.addTable(table);

    if (store != null) {
      commands.addAll(store.createTable(table, isTemporary: isTemporary));
    }
  }

  /// Validates and renames a table in [schema].
  void renameTable(String currentTableName, String newName) {
    var table = schema.tableForName(currentTableName);
    if (table == null) {
      throw SchemaException("Table $currentTableName does not exist.");
    }

    schema.renameTable(table, newName);
    if (store != null) {
      commands.addAll(store.renameTable(table, newName));
    }
  }

  /// Validates and deletes a table in [schema].
  void deleteTable(String tableName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    schema.removeTable(table);

    if (store != null) {
      commands.addAll(store.deleteTable(table));
    }
  }

  void alterTable(String tableName, void modify(SchemaTable targetTable)) {
    var existingTable = schema.tableForName(tableName);
    if (existingTable == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    var newTable = SchemaTable.from(existingTable);
    modify(newTable);
    schema.removeTable(existingTable);
    schema.addTable(newTable);

    if (store != null) {
      var shouldAddUnique = existingTable.uniqueColumnSet == null &&
          newTable.uniqueColumnSet != null;
      var shouldRemoveUnique = existingTable.uniqueColumnSet != null &&
          newTable.uniqueColumnSet == null;
      if (shouldAddUnique) {
        commands.addAll(store.addTableUniqueColumnSet(newTable));
      } else if (shouldRemoveUnique) {
        commands.addAll(store.deleteTableUniqueColumnSet(newTable));
      } else if (existingTable.uniqueColumnSet != null &&
          newTable.uniqueColumnSet != null) {
        var haveSameLength = existingTable.uniqueColumnSet.length ==
            newTable.uniqueColumnSet.length;
        var haveSameKeys = existingTable.uniqueColumnSet
            .every((s) => newTable.uniqueColumnSet.contains(s));

        if (!haveSameKeys || !haveSameLength) {
          commands.addAll(store.deleteTableUniqueColumnSet(newTable));
          commands.addAll(store.addTableUniqueColumnSet(newTable));
        }
      }
    }
  }

  /// Validates and adds a column to a table in [schema].
  void addColumn(String tableName, SchemaColumn column,
      {String unencodedInitialValue}) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    table.addColumn(column);
    if (store != null) {
      commands.addAll(store.addColumn(table, column,
          unencodedInitialValue: unencodedInitialValue));
    }
  }

  /// Validates and deletes a column in a table in [schema].
  void deleteColumn(String tableName, String columnName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    var column = table.columnForName(columnName);
    if (column == null) {
      throw SchemaException("Column $columnName does not exists.");
    }

    table.removeColumn(column);

    if (store != null) {
      commands.addAll(store.deleteColumn(table, column));
    }
  }

  /// Validates and renames a column in a table in [schema].
  void renameColumn(String tableName, String columnName, String newName) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    var column = table.columnForName(columnName);
    if (column == null) {
      throw SchemaException("Column $columnName does not exists.");
    }

    table.renameColumn(column, newName);

    if (store != null) {
      commands.addAll(store.renameColumn(table, column, newName));
    }
  }

  /// Validates and alters a column in a table in [schema].
  ///
  /// Alterations are made by setting properties of the column passed to [modify]. If the column's nullability
  /// changes from nullable to not nullable,  all previously null values for that column
  /// are set to the value of [unencodedInitialValue].
  ///
  /// Example:
  ///
  ///         database.alterColumn("table", "column", (c) {
  ///           c.isIndexed = true;
  ///           c.isNullable = false;
  ///         }), unencodedInitialValue: "0");
  void alterColumn(String tableName, String columnName,
      void modify(SchemaColumn targetColumn),
      {String unencodedInitialValue}) {
    var table = schema.tableForName(tableName);
    if (table == null) {
      throw SchemaException("Table $tableName does not exist.");
    }

    var existingColumn = table[columnName];
    if (existingColumn == null) {
      throw SchemaException("Column $columnName does not exist.");
    }

    var newColumn = SchemaColumn.from(existingColumn);
    modify(newColumn);

    if (existingColumn.type != newColumn.type) {
      throw SchemaException(
          "May not change column type for '${existingColumn.name}' in '$tableName' (${existingColumn.typeString} -> ${newColumn.typeString})");
    }

    if (existingColumn.autoincrement != newColumn.autoincrement) {
      throw SchemaException(
          "May not change column autoincrementing behavior for '${existingColumn.name}' in '$tableName'");
    }

    if (existingColumn.isPrimaryKey != newColumn.isPrimaryKey) {
      throw SchemaException(
          "May not change column primary key status for '${existingColumn.name}' in '$tableName'");
    }

    if (existingColumn.relatedTableName != newColumn.relatedTableName) {
      throw SchemaException(
          "May not change reference table for foreign key column '${existingColumn.name}' in '$tableName' (${existingColumn.relatedTableName} -> ${newColumn.relatedTableName})");
    }

    if (existingColumn.relatedColumnName != newColumn.relatedColumnName) {
      throw SchemaException(
          "May not change reference column for foreign key column '${existingColumn.name}' in '$tableName' (${existingColumn.relatedColumnName} -> ${newColumn.relatedColumnName})");
    }

    if (existingColumn.name != newColumn.name) {
      renameColumn(tableName, existingColumn.name, newColumn.name);
    }

    if (existingColumn.isNullable == true &&
        newColumn.isNullable == false &&
        unencodedInitialValue == null &&
        newColumn.defaultValue == null) {
      throw SchemaException(
          "May not change column '${existingColumn.name}' in '$tableName' to be nullable without defaultValue or unencodedInitialValue.");
    }

    table.replaceColumn(existingColumn, newColumn);

    if (store != null) {
      if (existingColumn.isIndexed != newColumn.isIndexed) {
        if (newColumn.isIndexed) {
          commands.addAll(store.addIndexToColumn(table, newColumn));
        } else {
          commands.addAll(store.deleteIndexFromColumn(table, newColumn));
        }
      }

      if (existingColumn.isUnique != newColumn.isUnique) {
        commands.addAll(store.alterColumnUniqueness(table, newColumn));
      }

      if (existingColumn.defaultValue != newColumn.defaultValue) {
        commands.addAll(store.alterColumnDefaultValue(table, newColumn));
      }

      if (existingColumn.isNullable != newColumn.isNullable) {
        commands.addAll(store.alterColumnNullability(
            table, newColumn, unencodedInitialValue));
      }

      if (existingColumn.deleteRule != newColumn.deleteRule) {
        commands.addAll(store.alterColumnDeleteRule(table, newColumn));
      }
    }
  }
}
