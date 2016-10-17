part of aqueduct;

class _PostgreSQLSchemaGenerator {
  String get _versionTableName => "_aqueduct_version_pgsql";

  List<String> createTable(SchemaTable table, {bool isTemporary: false}) {
    var columnString = table.columns.map((col) => _columnStringForColumn(col)).join(",");
    var tableCommand = "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} (${columnString})";

    var indexCommands = table.columns
        .where((col) => col.isIndexed && !col.isPrimaryKey) // primary keys are auto-indexed
        .map((col) => addIndexToColumn(table, col))
        .expand((commands) => commands);

    var constraintCommands = table.columns
        .where((sc) => sc.isForeignKey)
        .map((col) => _addConstraintsForColumn(table.name, col))
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
      commands.addAll(_addConstraintsForColumn(table.name, column));
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

  List<String> alterColumnNullability(SchemaTable table, SchemaColumn column, String unencodedInitialValue) {
    if (column.isNullable) {
      return ["ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP NOT NULL"];
    } else {
      if (unencodedInitialValue == null) {
        throw new SchemaException("Attempting to change column ${column.name} to 'not nullable', but no value specified to set values that are currently null in the database to avoid violating that constraint change.");
      }
      return [
        "UPDATE ${table.name} SET ${_columnNameForColumn(column)}=${unencodedInitialValue} WHERE ${_columnNameForColumn(column)} IS NULL",
        "ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} SET NOT NULL"
      ];
    }
  }

  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column) {
    // TODO: require data validation
    if (column.isUnique) {
      return ["ALTER TABLE ${table.name} ADD UNIQUE (${column.name})"];
    } else {
      return ["ALTER TABLE ${table.name} DROP CONSTRAINT ${_uniqueKeyName(table.name, column)}"];
    }
  }

  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column) {
    if (column.defaultValue != null) {
      return ["ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} SET DEFAULT ${column.defaultValue}"];
    } else {
      return ["ALTER TABLE ${table.name} ALTER COLUMN ${_columnNameForColumn(column)} DROP DEFAULT"];
    }
  }

  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column) {
    var allCommands = <String>[];
    allCommands.add("ALTER TABLE ONLY ${table.name} DROP CONSTRAINT ${_foreignKeyName(table.name, column)}");
    allCommands.addAll(_addConstraintsForColumn(table.name, column));
    return allCommands;
  }

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column) {
    return [
      "CREATE INDEX ${_indexNameForColumn(table.name, column)} ON ${table.name} (${_columnNameForColumn(column)})"
    ];
  }

  List<String> renameIndex(SchemaTable table, SchemaColumn column, String newIndexName) {
    var existingIndexName = _indexNameForColumn(table.name, column);
    return [
      "ALTER INDEX $existingIndexName RENAME TO $newIndexName"
    ];
  }

  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column) {
    return [
      "DROP INDEX ${_indexNameForColumn(table.name, column)}"
    ];
  }

  ////

  String _uniqueKeyName(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_key";
  }

  String _foreignKeyName(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_fkey";
  }

  List<String> _addConstraintsForColumn(String tableName, SchemaColumn column) {
    return [
      "ALTER TABLE ONLY ${tableName} ADD FOREIGN KEY (${_columnNameForColumn(column)}) "
          "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) "
          "ON DELETE ${_deleteRuleStringForDeleteRule(column._deleteRule)}"
    ];
  }

  String _indexNameForColumn(String tableName, SchemaColumn column) {
    return "${tableName}_${_columnNameForColumn(column)}_idx";
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
    switch (t._type) {
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

  SchemaTable get _versionTable {
    return new SchemaTable.empty()
      ..name = _versionTableName
      ..columns = [
        (new SchemaColumn.empty()..name = "versionNumber".._type = SchemaColumn.typeStringForType(PropertyType.integer)),
        (new SchemaColumn.empty()..name = "dateOfUpgrade".._type = SchemaColumn.typeStringForType(PropertyType.datetime)),
      ];
  }
}