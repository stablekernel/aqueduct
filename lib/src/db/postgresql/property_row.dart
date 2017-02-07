import 'property_mapper.dart';
import '../db.dart';

class RowMapper extends PropertyMapper with PredicateBuilder {
  RowMapper(this.type, ManagedPropertyDescription property,
      this.orderedMappers,
      {this.predicate, this.where})
      : super(property) {}

  ManagedEntity get entity => joinProperty.entity;
  PersistentJoinType type;
  ManagedObject where;
  QueryPredicate predicate;
  List<PropertyMapper> orderedMappers;
  Map<String, dynamic> substitutionVariables;

  String get name {
    ManagedRelationshipDescription p = property;
    return "${p.name}_${p.destinationEntity.primaryKey}";
  }

  ManagedPropertyDescription get joinProperty =>
      (property as ManagedRelationshipDescription).inverseRelationship;

  List<PropertyMapper> get flattened {
    return orderedMappers.expand((c) {
      if (c is RowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  String joinString;

  bool get isToMany {
    var rel = property as ManagedRelationshipDescription;

    return rel.relationshipType == ManagedRelationshipType.hasMany;
  }

  bool representsSameJoinAs(RowMapper other) {
    ManagedRelationshipDescription thisProperty = property;
    ManagedRelationshipDescription otherProperty = other.property;

    return thisProperty.destinationEntity == otherProperty.destinationEntity &&
        thisProperty.entity == otherProperty.entity &&
        thisProperty.name == otherProperty.name;
  }

  void build() {
    orderedMappers
        .where((p) => p is RowMapper)
        .forEach((p) => (p as RowMapper).build());

    var parentEntity = property.entity;
    var parentProperty = parentEntity.properties[parentEntity.primaryKey];
    var temporaryLeftElement = new PropertyToColumnMapper(parentProperty);

    var parentColumnName = temporaryLeftElement.columnName(withTableNamespace: true);

    // May need to make this less temporary - get it from another row mapper?
    var temporaryRightElement = new PropertyToColumnMapper(joinProperty);
    var childColumnName = temporaryRightElement.columnName(withTableNamespace: true);

    var joinPredicate = new QueryPredicate("$parentColumnName=$childColumnName", null);
    var finalPredicate = predicateFrom(where, [joinPredicate, predicate]);
    substitutionVariables = finalPredicate.parameters ?? {};

    // todo: incorporate alias!
    var thisJoin = "LEFT OUTER JOIN ${temporaryRightElement.property.entity.tableName} ON ${finalPredicate.format}";

    if (orderedMappers.any((p) => p is RowMapper)) {
      var nestedJoins = orderedMappers
          .where((p) => p is RowMapper)
          .map((p) {
            substitutionVariables.addAll((p as RowMapper).substitutionVariables);
            return (p as RowMapper).joinString;
          })
          .toList();
      nestedJoins.insert(0, thisJoin);
      joinString = nestedJoins.join(" ");
    } else {
      joinString = thisJoin;
    }
  }
}
