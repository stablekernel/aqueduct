part of aqueduct;

abstract class SchemaElement {
  Map<String, dynamic> asMap();
}

class SchemaException implements Exception {
  SchemaException(this.message);

  String message;
}

class Schema {
  Schema(this.tables);

  Schema.fromDataModel(DataModel dataModel) {
    tables = dataModel._entities.values.map((e) => new SchemaTable.fromEntity(e)).toList();
  }

  Schema.from(Schema otherSchema) {
    tables = otherSchema?.tables?.map((table) => new SchemaTable.from(table))?.toList() ?? [];
  }

  Schema.empty() {
    tables = [];
  }

  List<SchemaTable> tables;
  List<SchemaTable> get dependencyOrderedTables => _orderedTables([], tables);

  operator [](String tableName) => tableForName(tableName);

  bool matches(Schema schema) {
    if (schema.tables.length != tables.length) {
      return false;
    }

    return schema.tables.every((otherTable) {
      return tableForName(otherTable.name).matches(otherTable);
    });
  }

  void addTable(SchemaTable table) {
    if (tableForName(table.name) != null) {
      throw new SchemaException("Table ${table.name} already exist.");
    }

    tables.add(table);
  }

  void renameTable(SchemaTable table, String newName) {
    if (tableForName(newName) != null) {
      throw new SchemaException("Table ${newName} already exist.");
    }

    if (!tables.contains(table)) {
      throw new SchemaException("Table ${table.name} does not exist in schema.");
    }

    // Rename indices and constraints
    table.name = newName;
  }

  void removeTable(SchemaTable table) {
    if (!tables.contains(table)) {
      throw new SchemaException("Table ${table.name} does not exist in schema.");
    }

    tables.remove(table);
  }

  SchemaTable tableForName(String name) {
    var lowercaseName = name.toLowerCase();
    return tables.firstWhere((t) => t.name.toLowerCase() == lowercaseName, orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {
      "tables" : tables.map((t) => t.asMap()).toList()
    };
  }

  List<SchemaTable> _orderedTables(List<SchemaTable> tablesAccountedFor, List<SchemaTable> remainingTables) {
    if (remainingTables.isEmpty) {
      return tablesAccountedFor;
    }

    var tableIsReady = (SchemaTable t) {
      var foreignKeyColumns = t.columns.where((sc) => sc.relatedTableName != null).toList();

      if (foreignKeyColumns.isEmpty) {
        return true;
      }

      return foreignKeyColumns
          .map((sc) => sc.relatedTableName)
          .every((tableName) => tablesAccountedFor.map((st) => st.name).contains(tableName));
    };

    tablesAccountedFor.addAll(remainingTables.where(tableIsReady));

    return _orderedTables(tablesAccountedFor, remainingTables.where((st) => !tablesAccountedFor.contains(st)).toList());
  }
}
