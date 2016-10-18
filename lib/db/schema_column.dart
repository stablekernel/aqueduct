part of aqueduct;

class SchemaColumn {
  SchemaColumn(this.name, PropertyType t, {this.isIndexed: false, this.isNullable: false, this.autoincrement: false, this.isUnique: false, this.defaultValue, this.isPrimaryKey: false}) {
    _type = typeStringForType(t);
  }

  SchemaColumn.relationship(this.name, PropertyType t, {this.isNullable: true, this.isUnique: false, this.relatedTableName, this.relatedColumnName, RelationshipDeleteRule rule: RelationshipDeleteRule.nullify}) {
    isIndexed = true;
    _type = typeStringForType(t);
    _deleteRule = deleteRuleStringForDeleteRule(rule);
  }

  SchemaColumn.fromEntity(ModelEntity entity, PropertyDescription desc) {
    name = desc.name;

    if (desc is RelationshipDescription) {
      isPrimaryKey = false;
      relatedTableName = desc.destinationEntity.tableName;
      relatedColumnName = desc.destinationEntity.primaryKey;
      _deleteRule = deleteRuleStringForDeleteRule(desc.deleteRule);
    } else if (desc is AttributeDescription) {
      defaultValue = desc.defaultValue;
      isPrimaryKey = desc.isPrimaryKey;
    }

    _type = typeStringForType(desc.type);
    isNullable = desc.isNullable;
    autoincrement = desc.autoincrement;
    isUnique = desc.isUnique;
    isIndexed = desc.isIndexed;
  }

  SchemaColumn.from(SchemaColumn otherColumn) {
    name = otherColumn.name;
    _type = otherColumn._type;
    isIndexed = otherColumn.isIndexed;
    isNullable = otherColumn.isNullable;
    autoincrement = otherColumn.autoincrement;
    isUnique = otherColumn.isUnique;
    defaultValue = otherColumn.defaultValue;
    isPrimaryKey = otherColumn.isPrimaryKey;
    relatedTableName = otherColumn.relatedTableName;
    relatedColumnName = otherColumn.relatedColumnName;
    _deleteRule = otherColumn._deleteRule;
  }

  SchemaColumn.fromMap(Map<String, dynamic> map) {
    name = map["name"];
    _type = map["type"];
    isIndexed = map["indexed"];
    isNullable = map["nullable"];
    autoincrement = map["autoincrement"];
    isUnique = map["unique"];
    defaultValue = map["defaultValue"];
    isPrimaryKey = map["primaryKey"];
    relatedTableName = map["relatedTableName"];
    relatedColumnName = map["relatedColumnName"];
    _deleteRule = map["deleteRule"];
  }

  SchemaColumn.empty();

  String name;
  String _type;

  PropertyType get type => typeFromTypeString(_type);
  void set type(PropertyType t) {
    _type = typeStringForType(t);
  }


  bool isIndexed = false;
  bool isNullable = false;
  bool autoincrement = false;
  bool isUnique = false;
  String defaultValue;
  bool isPrimaryKey = false;

  String relatedTableName;
  String relatedColumnName;
  String _deleteRule;
  RelationshipDeleteRule get deleteRule => deleteRuleForDeleteRuleString(_deleteRule);
  void set deleteRule(RelationshipDeleteRule t) {
    _deleteRule = deleteRuleStringForDeleteRule(t);
  }

  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  bool matches(SchemaColumn otherColumn, [List<String> reasons]) {
    var matches = true;

    var symbols = [
      #name, #isIndexed, #type, #isNullable, #autoincrement, #isUnique, #defaultValue, #isPrimaryKey, #relatedTableName,
      #relatedColumnName, #deleteRule
    ];

    var receiverColumnMirror = reflect(this);
    var argColumnMirror = reflect(otherColumn);
    symbols.forEach((sym) {
      if (receiverColumnMirror.getField(sym).reflectee != argColumnMirror.getField(sym).reflectee) {
        matches = false;
        reasons?.add("\$table.${name} does not have same ${MirrorSystem.getName(sym)}.");
      }
    });

    return matches;
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

  static RelationshipDeleteRule deleteRuleForDeleteRuleString(String rule) {
    switch (rule) {
      case "cascade": return RelationshipDeleteRule.cascade;
      case "nullify": return RelationshipDeleteRule.nullify;
      case "restrict": return RelationshipDeleteRule.restrict;
      case "default": return RelationshipDeleteRule.setDefault;
    }
    return null;
  }

  Map<String, dynamic> asMap() {
    return {
      "name" : name,
      "type" : _type,
      "nullable" : isNullable,
      "autoincrement" : autoincrement,
      "unique" : isUnique,
      "defaultValue" : defaultValue,
      "primaryKey" : isPrimaryKey,
      "relatedTableName" : relatedTableName,
      "relatedColumnName" : relatedColumnName,
      "deleteRule" : _deleteRule,
      "indexed" : isIndexed
    };
  }

  String toString() => "$name $relatedTableName";
}