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

    List<SchemaForeignKeyConstraint> sortedConstraints = new List.from(table.foreignKeyConstraints);
    sortedConstraints.sort((a, b) => a.columnName.compareTo(b.columnName));
    constraintCommands.addAll(sortedConstraints.map((c) => _foreignKeyConstraintForTableConstraint(table, c)).toList());
  }

  String _foreignKeyConstraintForTableConstraint(SchemaTable sourceTable, SchemaForeignKeyConstraint constraint) =>
      "alter table only ${sourceTable.name} add foreign key (${constraint.columnName}) "
          "references ${constraint.foreignTableName} (${constraint.foreignColumnName}) "
          "on delete ${_deleteRuleStringForDeleteRule(constraint.deleteRule)};";

  String _indexStringForTableIndex(SchemaTable table, SchemaIndex i) =>
      "create index ${table.name}_${i.name}_idx on ${table.name} (${i.name});";

  String _columnStringForColumn(SchemaColumn col) {
    var elements = [col.name, _postgreSQLTypeForColumn(col)];

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