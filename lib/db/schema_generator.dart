part of aqueduct;

class SchemaGenerator {
  SchemaGenerator(PersistentStore persistentStore, DataModel dataModel, {String previousDataModelString: null}) {
    tables = dataModel.entities.values.map((e) => new SchemaTable(persistentStore, e)).toList();

    serialized = _buildOperationsFromPreviousDataModelString(previousDataModelString);
  }

  List<SchemaTable> tables;
  List serialized;

  List _buildOperationsFromPreviousDataModelString(String previousDataModelString) {
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
  SchemaTable(PersistentStore persistentStore, ModelEntity entity ) {
    name = entity.tableName;

    var validProperties = entity.properties.values
        .where((p) => (p is AttributeDescription) || (p is RelationshipDescription && p.relationshipType == RelationshipType.belongsTo))
        .toList();

    columns = validProperties
        .map((p) => new SchemaColumn(persistentStore, entity, p))
        .toList();

    foreignKeyConstraints = validProperties
      .where((p) => p is RelationshipDescription)
      .map((p) => new SchemaForeignKeyConstraints(p, columns))
      .toList();

    indexes = validProperties
        .where((p) => p.isIndexed)
        .map((p) => new SchemaIndex(persistentStore, p))
        .toList();
  }

  String name;
  List<SchemaColumn> columns;
  List<SchemaIndex> indexes;
  List<SchemaForeignKeyConstraints> foreignKeyConstraints;

  Map<String, dynamic> asSerializable() {
    return {
      "name" : name,
      "columns" : columns.map((c) => c.asSerializable()).toList(),
      "indexes" : indexes.map((i) => i.asSerializable()).toList(),
      "constraints" : foreignKeyConstraints.map((c) => c.asSerializable()).toList()
    };
  }

}

class SchemaColumn {
  SchemaColumn(PersistentStore persistentStore, ModelEntity entity, PropertyDescription desc) {
    _propertyName = desc.name;

    if (desc is RelationshipDescription) {
      name = persistentStore.foreignKeyForRelationshipDescription(desc);
      isPrimaryKey = false;
    } else if (desc is AttributeDescription) {
      name = desc.name;
      defaultValue = desc.defaultValue;
      isPrimaryKey = desc.isPrimaryKey;
    }

    type = typeStringForType(desc.type);
    isNullable = desc.isNullable;
    autoincrement = desc.autoincrement;
    isUnique = desc.isUnique;
  }

  String _propertyName;
  String name;
  String type;

  bool isNullable;
  bool autoincrement;
  bool isUnique;
  String defaultValue;
  bool isPrimaryKey;

  String typeStringForType(PropertyType type) {
    switch (type) {
      case PropertyType.integer: return "integer";
      case PropertyType.doublePrecision: return "double";
      case PropertyType.bigInteger: return "bigInteger";
      case PropertyType.boolean: return "boolean";
      case PropertyType.datetime: return "datetime";
      case PropertyType.string: return "string";
    }
  }

  Map<String, dynamic> asSerializable() {
    return {
      "name" : name,
      "type" : type,
      "nullable" : isNullable,
      "autoincrement" : autoincrement,
      "unique" : isUnique,
      "defaultValue" : defaultValue,
      "primaryKey" : isPrimaryKey
    };
  }
}


class SchemaForeignKeyConstraints {
  SchemaForeignKeyConstraints(RelationshipDescription desc, List<SchemaColumn> columns) {
    columnName = columns.firstWhere((sc) => sc._propertyName == desc.name).name;
    foreignTableName = desc.destinationEntity.tableName;
    foreignColumnName = desc.destinationEntity.primaryKey;
    deleteRule = deleteRuleStringForDeleteRule(desc.deleteRule);
  }

  String columnName;
  String foreignTableName;
  String foreignColumnName;
  String deleteRule;

  String deleteRuleStringForDeleteRule(RelationshipDeleteRule rule) {
    switch (rule) {
      case RelationshipDeleteRule.cascade: return "cascade";
      case RelationshipDeleteRule.nullify: return "nullify";
      case RelationshipDeleteRule.restrict: return "restrict";
      case RelationshipDeleteRule.setDefault: return "default";
    }
  }

  Map<String, dynamic> asSerializable() {
    return {
      "foreignTableName" : foreignTableName,
      "foreignColumnName" : foreignColumnName,
      "deleteRule" : deleteRule,
      "columnName" : columnName
    };
  }
}

class SchemaIndex {
  SchemaIndex(PersistentStore store, PropertyDescription desc) {
    if (desc is RelationshipDescription) {
      name = store.foreignKeyForRelationshipDescription(desc);
    } else {
      name = desc.name;
    }
  }

  String name;

  Map<String, dynamic> asSerializable() {
    return {
      "name" : name
    };
  }
}