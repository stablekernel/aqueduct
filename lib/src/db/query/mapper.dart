import '../query/query.dart';
import '../managed/managed.dart';
import '../managed/query_matchable.dart';

enum PersistentJoinType { leftOuter }

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
              "Property $propertyName is a hasMany or hasOne relationship and is invalid as a result property of "
              "${entity.tableName}, use matchOn.$propertyName.includeInResultSet = true instead.");
    }

    return property;
  }

  PropertyToColumnMapper(this.property);

  ManagedPropertyDescription property;
  String get name => property.name;

  String toString() {
    return "Mapper on $property";
  }
}

class PropertyToRowMapper extends PropertyToColumnMapper {
  PropertyToRowMapper(this.type, ManagedPropertyDescription property,
      this.predicate, this.orderedMappingElements)
      : super(property) {}

  PersistentJoinType type;
  QueryPredicate predicate;
  List<PropertyToColumnMapper> orderedMappingElements;

  String get name {
    ManagedRelationshipDescription p = property;
    return "${p.name}_${p.destinationEntity.primaryKey}";
  }

  ManagedPropertyDescription get joinProperty =>
      (property as ManagedRelationshipDescription).inverseRelationship;

  List<PropertyToColumnMapper> get flattened {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  List<PropertyToRowMapper> get orderedNestedRowMappings {
    return orderedMappingElements
        .where((e) => e is PropertyToRowMapper)
        .expand((e) {
      var a = [e];
      a.addAll((e as PropertyToRowMapper).orderedNestedRowMappings);
      return a;
    }).toList();
  }

  bool get isToMany {
    var rel = property as ManagedRelationshipDescription;

    return rel.relationshipType == ManagedRelationshipType.hasMany;
  }
}
