import '../db.dart';
import 'entity_table.dart';
import 'property_mapper.dart';

class PropertyToColumnMapper extends PropertyMapper {
  PropertyToColumnMapper(
      EntityTableMapper table, ManagedPropertyDescription property)
      : super(table, property);

  static List<PropertyToColumnMapper> fromKeys(
      EntityTableMapper table, ManagedEntity entity, List<String> keys) {
    // Ensure the primary key is always available and at 0th index.
    var primaryKeyIndex = keys.indexOf(entity.primaryKey);
    if (primaryKeyIndex == -1) {
      keys.insert(0, entity.primaryKey);
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, entity.primaryKey);
    }

    return keys
        .map((key) =>
            new PropertyToColumnMapper(table, propertyForName(entity, key)))
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

  bool isForeignKeyColumnAndWillBePopulatedByJoin = false;

  @override
  String toString() {
    return "Mapper on $property";
  }
}

class PropertyToColumnValue extends PropertyMapper {
  PropertyToColumnValue(
      EntityTableMapper table, ManagedPropertyDescription property, dynamic value)
      : super(table, property) {
    if (property is ManagedAttributeDescription) {
      if (property.isEnumeratedValue) {
        value = property.encodePrimitiveValue(value);
      }
    }

    this.value = value;
  }

  dynamic value;
}
