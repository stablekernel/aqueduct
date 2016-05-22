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

  String get columnName => name;
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
    var valueType = reflect(dartValue).type;
    switch(type) {
      case PropertyType.integer: return valueType.isSubtypeOf(reflectType(int));
      case PropertyType.bigInteger: return valueType.isSubtypeOf(reflectType(int));
      case PropertyType.boolean: return valueType.isSubtypeOf(reflectType(bool));
      case PropertyType.datetime: return valueType.isSubtypeOf(reflectType(DateTime));
      case PropertyType.doublePrecision: return valueType.isSubtypeOf(reflectType(double));
      case PropertyType.string: return valueType.isSubtypeOf(reflectType(String));
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
}

class RelationshipDescription extends PropertyDescription {
  RelationshipDescription(ModelEntity entity, String name, PropertyType type, this.destinationEntity, this.deleteRule, this.relationshipType, this.inverseKey, {bool unique: false, bool indexed: false, bool nullable: false, bool includedInDefaultResultSet: true})
    : super(entity, name, type, unique: unique, indexed: indexed, nullable: nullable, includedInDefaultResultSet: includedInDefaultResultSet) {

  }

  final ModelEntity destinationEntity;
  final RelationshipDeleteRule deleteRule;
  final RelationshipType relationshipType;
  final String inverseKey;

  @override
  String get columnName => (relationshipType == RelationshipType.belongsTo ? entity.dataModel.persistentStore.foreignKeyForRelationshipDescription(this) : null);
  RelationshipDescription get inverseRelationship => destinationEntity.relationships[inverseKey];

  bool isAssignableWith(dynamic dartValue) {
    var type = reflect(dartValue).type;

    if (type.isSubtypeOf(reflectType(List))) {
      if (relationshipType != RelationshipType.hasMany) {
        throw new DataModelException("Trying to assign List to relationship that isn't hasMany for ${MirrorSystem.getName(entity.persistentInstanceTypeMirror.simpleName)} $name");
      }
      type = type.typeArguments.first;
    }

    return type == destinationEntity.instanceTypeMirror;
  }
}