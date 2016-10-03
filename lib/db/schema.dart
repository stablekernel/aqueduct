part of aqueduct;

abstract class SchemaElement {
  Map<String, dynamic> asMap();
}

class Schema {
  Schema(DataModel dataModel) {
    tables = dataModel._entities.values.map((e) => new SchemaTable(e)).toList();
  }

  Schema.from(Schema otherSchema) {
    tables = otherSchema?.tables?.map((table) => new SchemaTable.from(table))?.toList() ?? [];
  }

  Schema.empty() {
    tables = [];
  }

  List<SchemaTable> tables;
  List<SchemaTable> get dependencyOrderedTables => _orderedTables([], tables);

  void addTable(SchemaTable table) {
    if (tableForName(table.name) != null) {
      throw new SchemaException("Table ${table.name} already exist.");
    }

    tables.add(table);
  }

  void deleteTable(SchemaTable table) {
    if (tableForName(table.name) == null) {
      throw new SchemaException("Table ${table.name} does not exist.");
    }

    tables.removeWhere((t) => t.name == table.name);
  }

  void renameTable(SchemaTable table, String newName) {
    if (tableForName(table.name) == null) {
      throw new SchemaException("Table ${newName} does not exist.");
    }

    if (tableForName(newName) != null) {
      throw new SchemaException("Table ${newName} already exist.");
    }

    tableForName(table.name).name = newName;
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

class SchemaTable extends SchemaElement {
  SchemaTable(ModelEntity entity) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) => (p is AttributeDescription && !p.isTransient) || (p is RelationshipDescription && p.relationshipType == RelationshipType.belongsTo))
        .toList();

    columns = validProperties
        .map((p) => new SchemaColumn(entity, p))
        .toList();
  }

  SchemaTable.from(SchemaTable otherTable) {
    name = otherTable.name;
    columns = otherTable.columns.map((col) => new SchemaColumn.from(col)).toList();
  }

  String name;
  List<SchemaColumn> columns;

  void addColumn(SchemaColumn column) {
    if (columnForName(column.name) != null) {
      throw new SchemaException("Column ${column.name} already exists.");
    }

    columns.add(column);
  }

  void renameColumn(SchemaColumn column, String newName) {
    if (columnForName(column.name) == null) {
      throw new SchemaException("Column ${column.name} does not exists.");
    }

    if (columnForName(newName) != null) {
      throw new SchemaException("Column ${newName} already exists.");
    }

    if (column.isPrimaryKey) {
      throw new SchemaException("May not rename primary key column (${column.name} -> ${newName})");
    }

    columnForName(column.name).name = newName;
  }

  void deleteColumn(SchemaColumn column) {
    if (columnForName(column.name) == null) {
      throw new SchemaException("Column ${column.name} does not exists.");
    }

    columns.removeWhere((c) => c.name == column.name);
  }

  void alterColumn(SchemaColumn newColumn) {
    // TODO: change delete rule at same time nullability is changed hsould be ok
    var existingColumn = columnForName(newColumn.name);
    if (existingColumn == null) {
      throw new SchemaException("Column ${existingColumn.name} does not exists.");
    }

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

    var idx = columns.indexOf(existingColumn);
    columns[idx] = newColumn;
  }

  SchemaColumn columnForName(String name) {
    var lowercaseName = name.toLowerCase();
    return columns.firstWhere((col) => col.name.toLowerCase() == lowercaseName, orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {
      "name" : name,
      "columns" : columns.map((c) => c.asMap()).toList()
    };
  }

  String toString() => name;
}

class SchemaColumn extends SchemaElement {
  SchemaColumn(ModelEntity entity, PropertyDescription desc) {
    name = desc.name;

    if (desc is RelationshipDescription) {
      isPrimaryKey = false;
      relatedTableName = desc.destinationEntity.tableName;
      relatedColumnName = desc.destinationEntity.primaryKey;
      deleteRule = deleteRuleStringForDeleteRule(desc.deleteRule);
    } else if (desc is AttributeDescription) {
      defaultValue = desc.defaultValue;
      isPrimaryKey = desc.isPrimaryKey;
    }

    type = typeStringForType(desc.type);
    isNullable = desc.isNullable;
    autoincrement = desc.autoincrement;
    isUnique = desc.isUnique;
    isIndexed = desc.isIndexed;
  }

  SchemaColumn.from(SchemaColumn otherColumn) {
    name = otherColumn.name;
    type = otherColumn.type;
    isIndexed = otherColumn.isIndexed;
    isNullable = otherColumn.isNullable;
    autoincrement = otherColumn.autoincrement;
    isUnique = otherColumn.isUnique;
    defaultValue = otherColumn.defaultValue;
    isPrimaryKey = otherColumn.isPrimaryKey;
    relatedTableName = otherColumn.relatedTableName;
    relatedColumnName = otherColumn.relatedColumnName;
    deleteRule = otherColumn.deleteRule;
  }

  String name;
  String type;

  bool isIndexed;
  bool isNullable;
  bool autoincrement;
  bool isUnique;
  String defaultValue;
  bool isPrimaryKey;

  String relatedTableName;
  String relatedColumnName;
  String deleteRule;

  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  String typeStringForType(PropertyType type) {
    switch (type) {
      case PropertyType.integer: return "integer";
      case PropertyType.doublePrecision: return "double";
      case PropertyType.bigInteger: return "bigInteger";
      case PropertyType.boolean: return "boolean";
      case PropertyType.datetime: return "datetime";
      case PropertyType.string: return "string";
      case PropertyType.transientList: return null;
      case PropertyType.transientMap: return null;
    }
    return null;
  }

  String deleteRuleStringForDeleteRule(RelationshipDeleteRule rule) {
    switch (rule) {
      case RelationshipDeleteRule.cascade: return "cascade";
      case RelationshipDeleteRule.nullify: return "nullify";
      case RelationshipDeleteRule.restrict: return "restrict";
      case RelationshipDeleteRule.setDefault: return "default";
    }
    return null;
  }

  Map<String, dynamic> asMap() {
    return {
      "name" : name,
      "type" : type,
      "nullable" : isNullable,
      "autoincrement" : autoincrement,
      "unique" : isUnique,
      "defaultValue" : defaultValue,
      "primaryKey" : isPrimaryKey,
      "relatedTableName" : relatedTableName,
      "relatedColumnName" : relatedColumnName,
      "deleteRule" : deleteRule,
      "indexed" : isIndexed
    };
  }

  String toString() => "$name $relatedTableName";
}

class SchemaException implements Exception {
  SchemaException(this.message);

  String message;
}