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
    matcherExpressions
        .where((expr) => !identical(expr.table, this))
        .forEach((expr) {
          if (expr.predicate?.parameters != null) {
              variables.addAll(expr.predicate.parameters);
          }
        });

    return variables;
  }

  List<PropertyToColumnMapper> get flattened {
    return returningOrderedMappers.fold([], (prev, c) {
      if (c is RowMapper) {
        prev.addAll(c.flattened);
      } else {
        prev.add(c);
      }
      return prev;
    });
  }

  void _buildMatcher() {
    _implicitRowMappers = <RowMapper>[];
    _matcherExpressions = propertyExpressionsFromObject(whereBuilder, _implicitRowMappers);
    addRowMappers(_implicitRowMappers);
  }

  List<RowMapper> _implicitRowMappers;
  List<RowMapper> get implicitRowMappers {
    if (_implicitRowMappers == null) {
      _buildMatcher();
    }

    return _implicitRowMappers;
  }

  List<PropertyExpression> _matcherExpressions;
  List<PropertyExpression> get matcherExpressions {
    if (_matcherExpressions == null) {
      _buildMatcher();
    }

    return _matcherExpressions;
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
      var filterPredicates = matcherExpressions
        .where((expr) => identical(expr.table, this))
        .map((expr) => expr.predicate)
        .toList();
      filterPredicates.add(joinPredicate);
      if (predicate != null) {
        filterPredicates.add(predicate);
      }
      _joinCondition = QueryPredicate.andPredicates(filterPredicates);
    }

    return _joinCondition;
  }

  void addRowMappers(List<RowMapper> rowMappers) {
    rowMappers.forEach((r) => r.parentTable = this);
    returningOrderedMappers.addAll(rowMappers);
  }

  String get innerSelectString {
    var nestedJoins = returningOrderedMappers
        .where((m) => m is RowMapper)
        .map((rm) => (rm as RowMapper).joinString)
        .join(" ");

    var flattenedColumns = flattened;
    var columnsWithNamespace = flattenedColumns
        .map((p) => p.columnName(withTableNamespace: true))
        .join(",");
    var columnsWithoutNamespace = flattenedColumns
        .map((p) => p.columnName())
        .join(",");

    var outerWhere = QueryPredicate.andPredicates(matcherExpressions
      .where((expr) => !identical(expr.table, this))
      .map((expr) => expr.predicate));
    var outerWhereString = "";
    if (outerWhere != null) {
      outerWhereString = " WHERE ${outerWhere.format}";
    }

    var selectString = "SELECT $columnsWithNamespace FROM $tableDefinition $nestedJoins";
    var alias = "${tableReference}(${columnsWithoutNamespace})";
    return "LEFT OUTER JOIN ($selectString$outerWhereString) $alias ON ${joinCondition.format}";
  }

  String get joinString {
    if (implicitRowMappers.length > 0) {
      return innerSelectString;
    }

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
