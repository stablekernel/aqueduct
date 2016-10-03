part of aqueduct;

class PostgreSQLSchemaGenerator {
  List<String> createTable(SchemaTable table, {bool isTemporary: false}) {
    var columnString = table.columns.map((col) => _columnStringForColumn(col)).join(",");
    var tableCommand = "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} (${columnString})";

    var indexCommands = table.columns
        .where((col) => col.isIndexed)
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);

    var constraintCommands = table.columns
        .where((sc) => sc.isForeignKey)
        .map((col) => _addConstraintsForColumn(table, col))
        .expand((commands) => commands);

    return [[tableCommand], indexCommands, constraintCommands].expand((cmds) => cmds).toList();
  }

  List<String> renameTable(SchemaTable table, String name) {
    // Must rename indices, constraints, etc.
    throw new UnsupportedError("renameTable is not yet supported.");
  }

  List<String> deleteTable(SchemaTable table) {
    return ["DROP TABLE ${table.name}"];
  }

  List<String> addColumn(SchemaTable table, SchemaColumn column) {
    var commands = [
      "ALTER TABLE ${table.name} ADD COLUMN ${_columnStringForColumn(column)}"
    ];

    if (column.isIndexed) {
      commands.addAll(addIndexToColumn(table, column));
    }

    if (column.isForeignKey) {
      commands.addAll(_addConstraintsForColumn(table, column));
    }

    return commands;
  }

  List<String> deleteColumn(SchemaTable table, SchemaColumn column) {
    return [
      "ALTER TABLE ${table.name} DROP COLUMN ${_columnNameForColumn(column)} ${column.relatedColumnName != null ? "CASCADE" : "RESTRICT"}"
    ];
  }

  List<String> renameColumn(SchemaTable table, SchemaColumn column, String name) {
    // Must rename indices, constraints, etc.
    throw new UnsupportedError("renameColumn is not yet supported.");
  }

  List<String> alterColumn(SchemaTable table, SchemaColumn existingColumn, SchemaColumn targetColumn, {String unencodedInitialValue}) {
    var allCommands = <String>[];
    if (existingColumn.isIndexed != targetColumn.isIndexed) {
      if (targetColumn.isIndexed) {
        allCommands.addAll(addIndexToColumn(table, existingColumn));
      } else {
        allCommands.addAll(deleteIndexFromColumn(table, existingColumn));
      }
    }

    if (existingColumn.isNullable != targetColumn.isNullable) {
      if (targetColumn.isNullable) {
        allCommands.add("ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(existingColumn)} DROP NOT NULL");
      } else {
        allCommands.add("UPDATE ${table.name} SET ${_columnNameForColumn(existingColumn)}=${unencodedInitialValue} WHERE ${_columnNameForColumn(existingColumn)} IS NULL");
        allCommands.add("ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(existingColumn)} SET NOT NULL");
      }
    }

    if (existingColumn.isUnique != targetColumn.isUnique) {
      // TODO: require data validation
      if (targetColumn.isUnique) {
        allCommands.add("ALTER TABLE ${table.name} add unique (${existingColumn.name})");
      } else {
        allCommands.add("ALTER TABLE ${table.name} DROP CONSTRAINT ${_uniqueKeyName(table, existingColumn)}");
      }
    }

    if (existingColumn.defaultValue != targetColumn.defaultValue) {
      if (targetColumn.defaultValue != null) {
        allCommands.add("ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(existingColumn)} SET DEFAULT ${targetColumn.defaultValue}");
      } else {
        allCommands.add("ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(existingColumn)} DROP DEFAULT");
      }
    }

    if (existingColumn.deleteRule != targetColumn.deleteRule) {
      allCommands.add("ALTER TABLE ONLY ${table.name} DROP CONSTRAINT ${_foreignKeyName(table, existingColumn)}");
      allCommands.addAll(_addConstraintsForColumn(table, targetColumn));
    }

    return allCommands;
  }

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    return [
      "CREATE INDEX ${_indexNameForColumn(table, column)} ON ${table.name} (${_columnNameForColumn(column)})"
    ];
  }

  List<String> renameIndex(String existingIndexName, String newIndexName) {
    return [
      "ALTER INDEX $existingIndexName RENAME TO $newIndexName"
    ];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${_indexNameForColumn(table, column)}"
    ];
  }

  ////

  String _uniqueKeyName(SchemaTable table, SchemaColumn column) {
    return "${table.name}_${_columnNameForColumn(column)}_key";
  }

  String _foreignKeyName(SchemaTable table, SchemaColumn column) {
    return "${table.name}_${_columnNameForColumn(column)}_fkey";
  }

  List<String> _addConstraintsForColumn(SchemaTable table, SchemaColumn column) {
    return [
      "ALTER TABLE ONLY ${table.name} ADD FOREIGN KEY (${_columnNameForColumn(column)}) "
          "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) "
          "ON DELETE ${_deleteRuleStringForDeleteRule(column.deleteRule)}"
    ];
  }

  String _indexNameForColumn(SchemaTable table, SchemaColumn column) {
    return "${table.name}_${_columnNameForColumn(column)}_idx";
  }

  List<String> renameIndexOnColumn(SchemaTable table, SchemaColumn column, String targetIndexName) {
    throw new UnsupportedError("renameColumn is not yet supported.");
  }

  String _columnStringForColumn(SchemaColumn col) {
    var elements = [_columnNameForColumn(col), _postgreSQLTypeForColumn(col)];
    if (col.isPrimaryKey) {
      elements.add("PRIMARY KEY");
    } else {
      elements.add(col.isNullable ? "NULL" : "NOT NULL");
      if (col.defaultValue != null) {
        elements.add("DEFAULT ${col.defaultValue}");
      }
      if (col.isUnique) {
        elements.add("UNIQUE");
      }
    }

    return elements.join(" ");
  }

  String _columnNameForColumn(SchemaColumn column) {
    if (column.relatedColumnName != null) {
      return "${column.name}_${column.relatedColumnName}";
    }

    return column.name;
  }

  String _deleteRuleStringForDeleteRule(String deleteRule) {
    switch (deleteRule) {
      case "cascade":
        return "CASCADE";
      case "restrict":
        return "RESTRICT";
      case "default":
        return "SET DEFAULT";
      case "nullify":
        return "SET NULL";
    }

    return null;
  }

  String _postgreSQLTypeForColumn(SchemaColumn t) {
    switch (t.type) {
      case "integer": {
        if (t.autoincrement) {
          return "SERIAL";
        }
        return "INT";
      } break;
      case "bigInteger": {
        if (t.autoincrement) {
          return "BIGSERIAL";
        }
        return "BIGINT";
      } break;
      case "string":
        return "TEXT";
      case "datetime":
        return "TIMESTAMP";
      case "boolean":
        return "BOOLEAN";
      case "double":
        return "DOUBLE PRECISION";
    }

    return null;
  }
}