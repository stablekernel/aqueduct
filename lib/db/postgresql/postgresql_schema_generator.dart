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

    tableCommands.add("create${isTemporary ? " temporary " : " "}table ${table.name} (${columnString});");

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
      "alter table only ${sourceTable.name} add foreign key (${_columnNameForColumn(column)}) "
          "references ${column.relatedTableName} (${column.relatedColumnName}) "
          "on delete ${_deleteRuleStringForDeleteRule(column.deleteRule)};";

  String _indexStringForTableIndex(SchemaTable table, SchemaIndex i) {
    var actualColumn = table.columns.firstWhere((col) => col.name == i.name);
    return "create index ${table.name}_${_columnNameForColumn(actualColumn)}_idx on ${table.name} (${_columnNameForColumn(actualColumn)});";
  }

  String _columnStringForColumn(SchemaColumn col) {
    var elements = [_columnNameForColumn(col), _postgreSQLTypeForColumn(col)];
    if (col.isPrimaryKey) {
      elements.add("primary key");
    } else {
      elements.add(col.isNullable ? "null" : "not null");
      if (col.defaultValue != null) {
        elements.add("default ${col.defaultValue}");
      }
      if (col.isUnique) {
        elements.add("unique");
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
        return "cascade";
      case "restrict":
        return "restrict";
      case "default":
        return "set default";
      case "nullify":
        return "set null";
    }

    return null;
  }

  String _postgreSQLTypeForColumn(SchemaColumn t) {
    switch (t.type) {
      case "integer": {
        if (t.autoincrement) {
          return "serial";
        }
        return "int";
      } break;
      case "bigInteger": {
        if (t.autoincrement) {
          return "bigserial";
        }
        return "bigint";
      } break;
      case "string":
        return "text";
      case "datetime":
        return "timestamp";
      case "boolean":
        return "boolean";
      case "double":
        return "double precision";
    }

    return null;
  }
}