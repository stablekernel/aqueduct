part of aqueduct;

/// Represents a database column for a [SchemaTable].
///
/// Use this class during migration to add, delete and modify columns.
class SchemaColumn {
  SchemaColumn(this.name, ManagedPropertyType t,
      {this.isIndexed: false,
      this.isNullable: false,
      this.autoincrement: false,
      this.isUnique: false,
      this.defaultValue,
      this.isPrimaryKey: false}) {
    _type = typeStringForType(t);
  }

  SchemaColumn.relationship(this.name, ManagedPropertyType t,
      {this.isNullable: true,
      this.isUnique: false,
      this.relatedTableName,
      this.relatedColumnName,
      ManagedRelationshipDeleteRule rule:
          ManagedRelationshipDeleteRule.nullify}) {
    isIndexed = true;
    _type = typeStringForType(t);
    _deleteRule = deleteRuleStringForDeleteRule(rule);
  }

  SchemaColumn.fromEntity(
      ManagedEntity entity, ManagedPropertyDescription desc) {
    name = desc.name;

    if (desc is ManagedRelationshipDescription) {
      isPrimaryKey = false;
      relatedTableName = desc.destinationEntity.tableName;
      relatedColumnName = desc.destinationEntity.primaryKey;
      _deleteRule = deleteRuleStringForDeleteRule(desc.deleteRule);
    } else if (desc is ManagedAttributeDescription) {
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

  ManagedPropertyType get type => typeFromTypeString(_type);
  void set type(ManagedPropertyType t) {
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
  ManagedRelationshipDeleteRule get deleteRule =>
      deleteRuleForDeleteRuleString(_deleteRule);
  void set deleteRule(ManagedRelationshipDeleteRule t) {
    _deleteRule = deleteRuleStringForDeleteRule(t);
  }

  bool get isForeignKey {
    return relatedTableName != null && relatedColumnName != null;
  }

  /// Whether or not two columns match.
  ///
  /// If passing [reasons], the reasons for a mismatch are added to the passed in [List].
  bool matches(SchemaColumn otherColumn, [List<String> reasons]) {
    var matches = true;

    var symbols = [
      #name,
      #isIndexed,
      #type,
      #isNullable,
      #autoincrement,
      #isUnique,
      #defaultValue,
      #isPrimaryKey,
      #relatedTableName,
      #relatedColumnName,
      #deleteRule
    ];

    var receiverColumnMirror = reflect(this);
    var argColumnMirror = reflect(otherColumn);
    symbols.forEach((sym) {
      if (receiverColumnMirror.getField(sym).reflectee !=
          argColumnMirror.getField(sym).reflectee) {
        matches = false;
        reasons?.add(
            "\$table.${name} does not have same ${MirrorSystem.getName(sym)}.");
      }
    });

    return matches;
  }

  static String typeStringForType(ManagedPropertyType type) {
    switch (type) {
      case ManagedPropertyType.integer:
        return "integer";
      case ManagedPropertyType.doublePrecision:
        return "double";
      case ManagedPropertyType.bigInteger:
        return "bigInteger";
      case ManagedPropertyType.boolean:
        return "boolean";
      case ManagedPropertyType.datetime:
        return "datetime";
      case ManagedPropertyType.string:
        return "string";
      case ManagedPropertyType.transientList:
        return null;
      case ManagedPropertyType.transientMap:
        return null;
    }
    return null;
  }

  static ManagedPropertyType typeFromTypeString(String type) {
    switch (type) {
      case "integer":
        return ManagedPropertyType.integer;
      case "double":
        return ManagedPropertyType.doublePrecision;
      case "bigInteger":
        return ManagedPropertyType.bigInteger;
      case "boolean":
        return ManagedPropertyType.boolean;
      case "datetime":
        return ManagedPropertyType.datetime;
      case "string":
        return ManagedPropertyType.string;
    }
    return null;
  }

  static String deleteRuleStringForDeleteRule(
      ManagedRelationshipDeleteRule rule) {
    switch (rule) {
      case ManagedRelationshipDeleteRule.cascade:
        return "cascade";
      case ManagedRelationshipDeleteRule.nullify:
        return "nullify";
      case ManagedRelationshipDeleteRule.restrict:
        return "restrict";
      case ManagedRelationshipDeleteRule.setDefault:
        return "default";
    }
    return null;
  }

  static ManagedRelationshipDeleteRule deleteRuleForDeleteRuleString(
      String rule) {
    switch (rule) {
      case "cascade":
        return ManagedRelationshipDeleteRule.cascade;
      case "nullify":
        return ManagedRelationshipDeleteRule.nullify;
      case "restrict":
        return ManagedRelationshipDeleteRule.restrict;
      case "default":
        return ManagedRelationshipDeleteRule.setDefault;
    }
    return null;
  }

  Map<String, dynamic> asMap() {
    return {
      "name": name,
      "type": _type,
      "nullable": isNullable,
      "autoincrement": autoincrement,
      "unique": isUnique,
      "defaultValue": defaultValue,
      "primaryKey": isPrimaryKey,
      "relatedTableName": relatedTableName,
      "relatedColumnName": relatedColumnName,
      "deleteRule": _deleteRule,
      "indexed": isIndexed
    };
  }

  String toString() => "$name $relatedTableName";
}
