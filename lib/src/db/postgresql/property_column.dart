import 'property_mapper.dart';
import '../db.dart';

class PropertyToColumnMapper extends PropertyMapper {
  static List<PropertyToColumnMapper> fromKeys(
      ManagedEntity entity, List<String> keys) {
    var primaryKeyIndex = keys.indexOf(entity.primaryKey);
    if (primaryKeyIndex == -1) {
      keys.insert(0, entity.primaryKey);
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, entity.primaryKey);
    }

    return keys
        .map((key) => new PropertyToColumnMapper(propertyForName(entity, key)))
        .toList();
  }

  static ManagedPropertyDescription propertyForName(
      ManagedEntity entity, String propertyName) {
    var property = entity.properties[propertyName];

    if (property == null) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Property $propertyName does not exist on ${entity.tableName}");
    }

    if (property is ManagedRelationshipDescription &&
        property.relationshipType != ManagedRelationshipType.belongsTo) {
      throw new QueryException(QueryExceptionEvent.internalFailure,
          message:
          "Property '$propertyName' is a hasMany or hasOne relationship and is invalid as a result property of "
              "'${entity.tableName}', use one of the join methods in 'Query<T>' instead.");
    }

    return property;
  }

  PropertyToColumnMapper(ManagedPropertyDescription property) : super(property);

  String get name => property.name;

  String toString() {
    return "Mapper on $property";
  }
}

class PropertyToColumnValue extends PropertyMapper {
  PropertyToColumnValue(ManagedPropertyDescription property, this.value)
      : super(property);

  String get name => property.name;
  dynamic value;
}
