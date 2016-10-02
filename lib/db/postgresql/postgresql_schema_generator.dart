part of aqueduct;

class PostgreSQLSchemaGenerator extends SchemaGeneratorBackend {
  PostgreSQLSchemaGenerator(List<Map> operations, {bool temporary: false}) : super(operations, temporary: temporary) {
    commands = [];
    commands.addAll(tableCommands);
    commands.addAll(indexCommands);
    commands.addAll(constraintCommands);
  }

  List<String> tableCommands = [];
  List<String> indexCommands = [];
  List<String> constraintCommands = [];


  void handleAddTableCommand(SchemaTable table) {
    List<SchemaColumn> sortedColumns = new List.from(table.columns);
    sortedColumns.sort((a, b) => a.name.compareTo(b.name));
    var columnString = sortedColumns.map((sc) => _columnStringForColumn(sc)).join(",");

    tableCommands.add("CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} (${columnString});");

    List<SchemaIndex> sortedIndexes = new List.from(table.indexes);
    sortedIndexes.sort((a, b) => a.name.compareTo(b.name));
    indexCommands.addAll(sortedIndexes.map((i) => _indexStringForTableIndex(table, i)).toList());

    List<SchemaColumn> sortedConstraints = table.columns
      .where((col) => col.relatedColumnName != null)
      .toList();
    sortedConstraints.sort((a, b) => a.name.compareTo(b.name));
    constraintCommands.addAll(sortedConstraints.map((c) => _foreignKeyConstraintForTableConstraint(table, c)).toList());
  }

  String _foreignKeyConstraintForTableConstraint(SchemaTable sourceTable, SchemaColumn column) =>
      "ALTER TABLE ONLY ${sourceTable.name} ADD FOREIGN KEY (${_columnNameForColumn(column)}) "
          "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) "
          "ON DELETE ${_deleteRuleStringForDeleteRule(column.deleteRule)};";

  String _indexStringForTableIndex(SchemaTable table, SchemaIndex i) {
    var actualColumn = table.columns.firstWhere((col) => col.name == i.name);
    return "CREATE INDEX ${table.name}_${_columnNameForColumn(actualColumn)}_idx ON ${table.name} (${_columnNameForColumn(actualColumn)});";
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