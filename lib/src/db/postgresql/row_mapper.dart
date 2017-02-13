import '../db.dart';
import 'entity_table.dart';
import 'predicate_builder.dart';
import 'property_mapper.dart';

class RowMapper extends PostgresMapper
    with PredicateBuilder, EntityTableMapper {
  RowMapper(this.type, this.joiningProperty, List<String> propertiesToFetch,
      {this.predicate, this.whereBuilder}) {
    returningOrderedMappers =
        PropertyToColumnMapper.fromKeys(this, entity, propertiesToFetch);
  }

  RowMapper.implicit(this.type, this.joiningProperty) {
    returningOrderedMappers = [];
  }

  ManagedRelationshipDescription joiningProperty;
  EntityTableMapper originatingTable;
  PersistentJoinType type;
  ManagedObject whereBuilder;
  QueryPredicate predicate;
  QueryPredicate _joinCondition;

  ManagedEntity get entity => joiningProperty.inverse.entity;

  ManagedRelationshipDescription get foreignKeyProperty =>
      joiningProperty.relationshipType == ManagedRelationshipType.belongsTo
        ? joiningProperty : joiningProperty.inverse;

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
    _matcherExpressions =
        propertyExpressionsFromObject(whereBuilder, _implicitRowMappers);
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
      PropertyToColumnMapper leftMapper, rightMapper;
      if (identical(foreignKeyProperty, joiningProperty)) {
        leftMapper = new PropertyToColumnMapper(originatingTable, joiningProperty);
        rightMapper = new PropertyToColumnMapper(this, joiningProperty.entity.primaryKeyAttribute);
      } else {
        leftMapper = new PropertyToColumnMapper(originatingTable, originatingTable.entity.primaryKeyAttribute);
        rightMapper = new PropertyToColumnMapper(this, joiningProperty.inverse);
      }

      var leftColumn = leftMapper.columnName(withTableNamespace: true);
      var rightColumn = rightMapper.columnName(withTableNamespace: true);
      var joinPredicate = new QueryPredicate("$leftColumn=$rightColumn", null);
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
    rowMappers.forEach((r) {
      r.originatingTable = this;
      returningOrderedMappers.removeWhere((m) {
        if (m is PropertyToColumnMapper) {
          return identical(m.property, r.joiningProperty);
        }

        return false;
      });
    });
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
    var columnsWithoutNamespace =
        flattenedColumns.map((p) => p.columnName()).join(",");

    var outerWhere = QueryPredicate.andPredicates(matcherExpressions
        .where((expr) => !identical(expr.table, this))
        .map((expr) => expr.predicate));
    var outerWhereString = "";
    if (outerWhere != null) {
      outerWhereString = " WHERE ${outerWhere.format}";
    }

    var selectString =
        "SELECT $columnsWithNamespace FROM $tableDefinition $nestedJoins";
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
    return joiningProperty.relationshipType == ManagedRelationshipType.hasMany;
  }

  bool representsRelationship(ManagedRelationshipDescription relationship) {
    return joiningProperty.destinationEntity == relationship.destinationEntity &&
        joiningProperty.entity == relationship.entity &&
        joiningProperty.name == relationship.name;
  }

  String generateTableAlias() {
    return originatingTable.generateTableAlias();
  }
}
