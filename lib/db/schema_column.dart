part of aqueduct;

class SchemaColumn extends SchemaElement {
  SchemaColumn(this.name, PropertyType t, {this.isIndexed: false, this.isNullable: false, this.autoincrement: false, this.isUnique: false, this.defaultValue, this.isPrimaryKey: false}) {
    type = typeStringForType(t);
  }

  SchemaColumn.relationship(this.name, PropertyType t, {this.isNullable: true, this.isUnique: false, this.relatedTableName, this.relatedColumnName, RelationshipDeleteRule rule: RelationshipDeleteRule.nullify}) {
    deleteRule = deleteRuleStringForDeleteRule(rule);
  }

  SchemaColumn.fromEntity(ModelEntity entity, PropertyDescription desc) {
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

  SchemaColumn.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    type = map["type"];
    isIndexed = map["indexed"];
    isNullable = map["nullable"];
    autoincrement = map["autoincrement"];
    isUnique = map["unique"];
    defaultValue = map["defaultValue"];
    isPrimaryKey = map["primaryKey"];
    relatedTableName = map["relatedTableName"];
    relatedColumnName = map["relatedColumnName"];
    deleteRule = map["deleteRule"];
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

  static PropertyType typeFromTypeString(String type) {
    switch (type) {
      case "integer": return PropertyType.integer;
      case "double": return PropertyType.doublePrecision;
      case "bigInteger": return PropertyType.bigInteger;
      case "boolean": return PropertyType.boolean;
      case "datetime": return PropertyType.datetime;
      case "string": return PropertyType.string;
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