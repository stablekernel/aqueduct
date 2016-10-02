part of aqueduct;

class SchemaGenerator {
  SchemaGenerator(DataModel dataModel, {String previousDataModelString: null}) {
    tables = dataModel._entities.values.map((e) => new SchemaTable(e)).toList();

    serialized = _buildOperationsFromPreviousDataModelString(previousDataModelString);
  }

  List<SchemaTable> tables;
  List<Map<String, dynamic>> serialized;

  List<Map<String, dynamic>> _buildOperationsFromPreviousDataModelString(String previousDataModelString) {
    if (previousDataModelString == null) {
      // Fresh, so only table.add
      return tables
          .map((t) => t.asSerializable())
          .map((s) => {"op" : "table.add", "table" : s})
          .toList();
    }

    return null;
  }
}

class SchemaTable {
  SchemaTable(ModelEntity entity ) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) => (p is AttributeDescription && !p.isTransient) || (p is RelationshipDescription && p.relationshipType == RelationshipType.belongsTo))
        .toList();

    columns = validProperties
        .map((p) => new SchemaColumn(entity, p))
        .toList();

    indexes = validProperties
        .where((p) => p.isIndexed)
        .map((p) => new SchemaIndex(p))
        .toList();
  }

  SchemaTable.fromJSON(Map<String, dynamic> json) {
    name = json["name"];
    columns = json["columns"].map((c) => new SchemaColumn.fromJSON(c)).toList();
    indexes = json["indexes"].map((c) => new SchemaIndex.fromJSON(c)).toList();
  }

  String name;
  List<SchemaColumn> columns;
  List<SchemaIndex> indexes;

  Map<String, dynamic> asSerializable() {
    return {
      "name" : name,
      "columns" : columns.map((c) => c.asSerializable()).toList(),
      "indexes" : indexes.map((i) => i.asSerializable()).toList()
    };
  }

}

class SchemaColumn {
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
  }

  SchemaColumn.fromJSON(Map<String, dynamic> json) {
    name = json["name"];
    type = json["type"];
    isNullable = json["nullable"];
    autoincrement = json["autoincrement"];
    isUnique = json["unique"];
    defaultValue = json["defaultValue"];
    isPrimaryKey = json["primaryKey"];

    relatedColumnName = json["relatedColumnName"];
    relatedTableName = json["relatedTableName"];
    deleteRule = json["deleteRule"];
  }

  String name;
  String type;

  bool isNullable;
  bool autoincrement;
  bool isUnique;
  String defaultValue;
  bool isPrimaryKey;

  String relatedTableName;
  String relatedColumnName;
  String deleteRule;

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

  Map<String, dynamic> asSerializable() {
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
    };
  }
}

class SchemaIndex {
  SchemaIndex(PropertyDescription desc) {
    name = desc.name;
  }

  SchemaIndex.fromJSON(Map<String, dynamic> json) {
    name = json["name"];
  }

  String name;

  Map<String, dynamic> asSerializable() {
    return {
      "name" : name
    };
  }
}

abstract class SchemaGeneratorBackend {
  SchemaGeneratorBackend(List<Map<String, dynamic>> operations, {bool temporary: false}) {
    isTemporary = temporary;
    operations.forEach((op) {
      _parseOperation(op);
    });
  }

  List<String> commands;
  bool isTemporary;

  String get commandList {
    return commands.join("\n");
  }

  void _parseOperation(Map<String, dynamic> operation) {
    switch(operation["op"]) {
      case "table.add" : handleAddTableCommand(new SchemaTable.fromJSON(operation["table"]));
    }

    return null;
  }

  void handleAddTableCommand(SchemaTable table);
}