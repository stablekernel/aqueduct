part of aqueduct;

class PostgreSQLSchemaGenerator {
  List<String> createTable(SchemaTable table, {bool isTemporary: false}) {
    var columnString = table.columns.map((col) => _columnStringForColumn(col)).join(",");
    var tableCommand = "CREATE${isTemporary ? " TEMPORARY " : " "}TABLE ${table.name} (${columnString})";

    var indexCommands = table.columns
        .where((col) => col.isIndexed)
        .map((col) => createIndicesForColumn(col))
        .expand((commands) => commands);

    var constraintCommands = table.columns
        .where((sc) => sc.isForeignKey)
        .map((col) => createConstraintsForColumn(col))
        .expand((commands) => commands);

    return [[tableCommand], indexCommands, constraintCommands].expand((cmds) => cmds).toList();
  }

  List<String> createIndicesForColumn(SchemaColumn column) {
    return [
      "CREATE INDEX ${column.table.name}_${_columnNameForColumn(column)}_idx ON ${column.table.name} (${_columnNameForColumn(column)})"
    ];
  }

  List<String> createConstraintsForColumn(SchemaColumn column) {
    return [
      "ALTER TABLE ONLY ${column.table.name} ADD FOREIGN KEY (${_columnNameForColumn(column)}) "
          "REFERENCES ${column.relatedTableName} (${column.relatedColumnName}) "
          "ON DELETE ${_deleteRuleStringForDeleteRule(column.deleteRule)}"
    ];
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