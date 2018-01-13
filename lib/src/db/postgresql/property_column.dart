import '../db.dart';
import 'entity_table.dart';
import 'property_mapper.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

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
      throw new ArgumentError("Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'.");
    }

    if (property is ManagedRelationshipDescription &&
        property.relationshipType != ManagedRelationshipType.belongsTo) {
      throw new ArgumentError("Could not construct query. Column '$propertyName' does not exist for table '${entity.tableName}'. "
          "'$propertyName' recognized as ORM relationship, use 'Query.join' instead.");
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
    this.value = convertValueForStorage(value);
  }

  dynamic value;
}
