import '../db.dart';
import 'entity_table.dart';
import 'predicate_builder.dart';
import 'property_mapper.dart';

class RowMapper extends PostgresMapper
    with PredicateBuilder, EntityTableMapper {
  RowMapper(this.type, this.parentProperty, List<String> propertiesToFetch,
      {this.predicate, this.whereBuilder}) {
    returningOrderedMappers =
        PropertyToColumnMapper.fromKeys(this, entity, propertiesToFetch);
  }

  RowMapper.implicit(this.type, this.parentProperty) {
    returningOrderedMappers = [];
  }

  ManagedRelationshipDescription parentProperty;
  EntityTableMapper parentTable;
  PersistentJoinType type;
  ManagedObject whereBuilder;
  QueryPredicate predicate;
  QueryPredicate _joinCondition;

  ManagedEntity get entity => inverseProperty.entity;
  ManagedPropertyDescription get inverseProperty =>
      parentProperty.inverseRelationship;

  Map<String, dynamic> get substitutionVariables {
    var variables = joinCondition.parameters ?? {};
    returningOrderedMappers.where((p) => p is RowMapper).forEach((p) {
      variables.addAll((p as RowMapper).substitutionVariables);
    });
    return variables;
  }

  List<PropertyToColumnMapper> get flattened {
    return returningOrderedMappers.expand((c) {
      if (c is RowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  QueryPredicate get joinCondition {
    if (_joinCondition == null) {
      var parentEntity = parentProperty.entity;
      var parentPrimaryKeyProperty =
          parentEntity.properties[parentEntity.primaryKey];
      var temporaryLeftElement =
          new PropertyToColumnMapper(parentTable, parentPrimaryKeyProperty);
      var parentColumnName =
          temporaryLeftElement.columnName(withTableNamespace: true);

      var temporaryRightElement =
          new PropertyToColumnMapper(this, inverseProperty);
      var childColumnName =
          temporaryRightElement.columnName(withTableNamespace: true);

      var joinPredicate =
          new QueryPredicate("$parentColumnName=$childColumnName", null);
      var implicitJoins = <RowMapper>[];
      _joinCondition = predicateFrom(
          whereBuilder, [joinPredicate, predicate], implicitJoins);
      addRowMappers(implicitJoins);
    }

    return _joinCondition;
  }

  void addRowMappers(List<RowMapper> rowMappers) {
    rowMappers.forEach((r) => r.parentTable = this);
    returningOrderedMappers.addAll(rowMappers);
  }

  String get joinString {
    var thisJoin =
        "LEFT OUTER JOIN ${tableDefinition} ON ${joinCondition.format}";

    if (returningOrderedMappers.any((p) => p is RowMapper)) {
      var nestedJoins =
          returningOrderedMappers.where((p) => p is RowMapper).map((p) {
        return (p as RowMapper).joinString;
      }).toList();
      nestedJoins.insert(0, thisJoin);
      return nestedJoins.join(" ");
    }

    return thisJoin;
  }

  bool get isToMany {
    return parentProperty.relationshipType == ManagedRelationshipType.hasMany;
  }

  bool representsRelationship(ManagedRelationshipDescription relationship) {
    return parentProperty.destinationEntity == relationship.destinationEntity &&
        parentProperty.entity == relationship.entity &&
        parentProperty.name == relationship.name;
  }

  String generateTableAlias() {
    return parentTable.generateTableAlias();
  }
}
