import '../query/query.dart';
import '../managed/managed.dart';
import '../managed/query_matchable.dart';

/// This enumeration is used internaly.
enum PersistentJoinType { leftOuter }

/// This class is used internally.
class PropertyToColumnMapper {
  static List<PropertyToColumnMapper> mappersForKeys(
      ManagedEntity entity, List<String> keys) {
    var primaryKeyIndex = keys.indexOf(entity.primaryKey);
    if (primaryKeyIndex == -1) {
      keys.insert(0, entity.primaryKey);
    } else if (primaryKeyIndex > 0) {
      keys.removeAt(primaryKeyIndex);
      keys.insert(0, entity.primaryKey);
    }

    return keys.map((key) {
      var property = propertyForName(entity, key);
      return new PropertyToColumnMapper(property);
    }).toList();
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
              "Property $propertyName is a hasMany or hasOne relationship and is invalid as a result property of ${entity
              .tableName}, use matchOn.$propertyName.includeInResultSet = true instead.");
    }

    return property;
  }

  PropertyToColumnMapper(this.property);

  ManagedPropertyDescription property;
  String get columnName => property.name;

  String toString() {
    return "Mapper on $property";
  }
}

/// This class is used internally.
class PropertyToRowMapping extends PropertyToColumnMapper {
  PropertyToRowMapping(this.type, ManagedPropertyDescription property,
      this.predicate, this.orderedMappingElements)
      : super(property) {}

  PersistentJoinType type;

  String get columnName {
    ManagedRelationshipDescription p = property;
    return "${p.name}_${p.destinationEntity.primaryKey}";
  }

  ManagedPropertyDescription get joinProperty =>
      (property as ManagedRelationshipDescription).inverseRelationship;
  QueryPredicate predicate;
  List<PropertyToColumnMapper> orderedMappingElements;

  List<PropertyToColumnMapper> get flattened {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapping) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  List<PropertyToRowMapping> get orderedNestedRowMappings {
    return orderedMappingElements
        .where((e) => e is PropertyToRowMapping)
        .expand((e) {
      var a = [e];
      a.addAll((e as PropertyToRowMapping).orderedNestedRowMappings);
      return a;
    }).toList();
  }

  bool get isToMany {
    var rel = property as ManagedRelationshipDescription;

    return rel.relationshipType == ManagedRelationshipType.hasMany;
  }
}
