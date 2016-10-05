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

  Schema.withTables(this.tables);

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
    tables.add(table);
  }

  void renameTable(SchemaTable table, String newName) {
    // Rename indices and constraints
    table.name = newName;
  }

  void removeTable(SchemaTable table) {
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

  SchemaTable.empty();

  SchemaTable.withColumns(this.name, this.columns);

  String name;
  List<SchemaColumn> columns;

  SchemaColumn operator [](String columnName) => columnForName(columnName);

  bool matches(SchemaTable table) {
    if (columns.length != table.columns.length) {
      return false;
    }

    return table.columns.every((otherColumn) {
      return columnForName(otherColumn.name).matches(otherColumn);
    });
  }

  void addColumn(SchemaColumn column) {
    columns.add(column);
  }

  void renameColumn(SchemaColumn column, String newName) {
    // We also must rename indices
    column.name = newName;
  }

  void removeColumn(SchemaColumn column) {
    columns.remove(column);
  }

  void replaceColumn(SchemaColumn existingColumn, SchemaColumn newColumn) {
    var index = columns.indexOf(existingColumn);
    columns[index] = newColumn;
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

  SchemaColumn.withName(this.name, PropertyType t) {
    type = typeStringForType(t);
  }

  SchemaColumn.empty();

  String name;
  String type;

  bool isIndexed = false;
  bool isNullable = false;
  bool autoincrement = false;
  bool isUnique = false;
  String defaultValue;
  bool isPrimaryKey = false;

  String relatedTableName;
  String relatedColumnName;
  String deleteRule;

  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  bool matches(SchemaColumn otherColumn) {
    return name == otherColumn.name
        && type == otherColumn.type
        && isIndexed == otherColumn.isIndexed
        && isNullable == otherColumn.isNullable
        && autoincrement == otherColumn.autoincrement
        && isUnique == otherColumn.isUnique
        && defaultValue == otherColumn.defaultValue
        && isPrimaryKey == otherColumn.isPrimaryKey
        && relatedTableName == otherColumn.relatedTableName
        && relatedColumnName == otherColumn.relatedColumnName
        && deleteRule == otherColumn.deleteRule;
  }

  static String typeStringForType(PropertyType type) {
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

  static String deleteRuleStringForDeleteRule(RelationshipDeleteRule rule) {
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