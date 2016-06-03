part of aqueduct;

enum PropertyType {
  integer,
  bigInteger,
  string,
  datetime,
  boolean,
  doublePrecision
}

class PropertyDescription {
  PropertyDescription(this.entity, this.name, this.type, {String explicitDatabaseType: null, bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true, bool autoincrement: false})
      : isUnique = unique,
        isIndexed = indexed,
        isNullable = nullable,
        isIncludedInDefaultResultSet = includedInDefaultResultSet,
        this.autoincrement = autoincrement {

  }

  final ModelEntity entity;

  final PropertyType type;

  final String name;
  final bool isUnique;
  final bool isIndexed;
  final bool isNullable;
  final bool isIncludedInDefaultResultSet;
  final bool autoincrement;

  static PropertyType propertyTypeForDartType(Type t) {
    switch (t) {
      case int:
        return PropertyType.integer;
      case String:
        return PropertyType.string;
      case DateTime:
        return PropertyType.datetime;
      case bool:
        return PropertyType.boolean;
      case double:
        return PropertyType.doublePrecision;
    }

    return null;
  }

  bool isAssignableWith(dynamic dartValue) {
    switch(type) {
      case PropertyType.integer: return dartValue is int;
      case PropertyType.bigInteger: return dartValue is int;
      case PropertyType.boolean: return dartValue is bool;
      case PropertyType.datetime: return dartValue is DateTime;
      case PropertyType.doublePrecision: return dartValue is double;
      case PropertyType.string: return dartValue is String;
    }
    return false;
  }
}

class AttributeDescription extends PropertyDescription {
  AttributeDescription(ModelEntity entity, String name, PropertyType type, {bool primaryKey: false, String defaultValue: null, bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true, bool autoincrement: false}) :
      super(entity, name, type, unique: unique, indexed: indexed, nullable: nullable, includedInDefaultResultSet: includedInDefaultResultSet, autoincrement: autoincrement),
      isPrimaryKey = primaryKey,
      this.defaultValue = defaultValue {

  }

  final bool isPrimaryKey;
  final String defaultValue;

  String toString() {
    return "AttributeDescription on ${entity.tableName}.$name Type: $type";
  }
}

class RelationshipDescription extends PropertyDescription {
  RelationshipDescription(ModelEntity entity, String name, PropertyType type, this.destinationEntity, this.deleteRule, this.relationshipType, this.inverseKey, {bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true})
    : super(entity, name, type, unique: unique, indexed: indexed, nullable: nullable, includedInDefaultResultSet: includedInDefaultResultSet) {

  }

  final ModelEntity destinationEntity;
  final RelationshipDeleteRule deleteRule;
  final RelationshipType relationshipType;
  final String inverseKey;

  RelationshipDescription get inverseRelationship => destinationEntity.relationships[inverseKey];

  bool isAssignableWith(dynamic dartValue) {
    var type = reflect(dartValue).type;

    if (type.isSubtypeOf(reflectType(List))) {
      if (relationshipType != RelationshipType.hasMany) {
        throw new DataModelException("Trying to assign List to relationship that isn't hasMany for ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} $name");
      }

      type = type.typeArguments.first;
      if (type == reflectType(dynamic)) {
        // We can't say for sure... so we have to assume it to be true at the current stage.
        return true;
      }
    }

    return type == destinationEntity.instanceTypeMirror;
  }

  String toString() {
    if (relationshipType == RelationshipType.belongsTo) {
      return "RelationshipDescription on ${entity.tableName}.$name Type: ${relationshipType} ($type)";
    }

    return "RelationshipDescription on ${entity.tableName}.$name Type: ${relationshipType}";
  }
}