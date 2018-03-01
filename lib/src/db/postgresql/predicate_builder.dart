import '../db.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/postgresql/mappers/expression.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/row.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

abstract class PredicateBuilder implements EntityTableMapper {
  @override
  ManagedEntity get entity;

  /// Translates QueryExpressions to ExpressionMappers.
  ///
  /// This function gets called 'recursively' in the sense that each table being selected
  /// invokes this method. If a predicate references a property in a related table,
  /// a join occurs. If the query does not currently join that table, an implicit row
  /// mapper is created and passed to subsequent invocations. This triggers a join
  /// but also allows other joins to disambiguate column names by prefixing the parameter
  /// name.
  List<ExpressionMapper> propertyExpressionsFromObject(
      List<QueryExpression<dynamic>> expressions, List<RowMapper> implicitRowMappers,
      {bool disambiguateVariableNames: false}) {
    if (expressions == null) {
      return [];
    }

    var prefix = disambiguateVariableNames ? "implicit_" : "";

    return expressions
        .map((expression) {
          final lastElement = expression.keyPath.path.last;
          if (lastElement is ManagedRelationshipDescription && lastElement.relationshipType != ManagedRelationshipType.belongsTo) {
            throw new StateError("Attempting to add expression directly to a has-one or has-many relationship property.");
          }

          // We're guaranteed that the last element is represented by a column

          bool isColumnInThisTable = expression.keyPath.length == 1;
          bool isForeignKeyInThisTable = expression.keyPath.length == 2 && lastElement is ManagedAttributeDescription && lastElement.isPrimaryKey;

          if (isColumnInThisTable) {
            return [
              new ExpressionMapper(
                  this, lastElement, expression.expression, additionalVariablePrefix: prefix)
            ];
          } else if (isForeignKeyInThisTable) {
            return [new ExpressionMapper(
                this, expression.keyPath.path.first, expression.expression, additionalVariablePrefix: prefix)];
          } else {
            // We're referencing a column on another table. We'll either create an implicit join on
            // the table, or if we're already joining on that table, we'll make sure to use that joined table.

            final thisTablesRelationshipProperty = expression.keyPath.path.first;
            bool disambiguate = true;

            // Let's see if we already have a join for this relationship
            RowMapper rowMapper = returningOrderedMappers
                .where((m) => m is RowMapper)
                .firstWhere((m) => (m as RowMapper).isJoinOnProperty(thisTablesRelationshipProperty),
                orElse: () => null);

            // If not, create an implicit join on this relationship
            if (rowMapper == null) {
              rowMapper = new RowMapper.implicit(PersistentJoinType.leftOuter, thisTablesRelationshipProperty);
              rowMapper.originatingTable = this;
              implicitRowMappers.add(rowMapper);
              disambiguate = false;
            }
//
//            if (innerMatcher is ManagedSet) {
//              innerMatcher = (innerMatcher as ManagedSet).haveAtLeastOneWhere;
//            }
//
            // Then build the expression relative to the joined table
            // We'll duplicate the expression object and lop off the key path
            // so that it can be resolved relative to the joined table.
            return rowMapper.propertyExpressionsFromObject(
                [new QueryExpression.from(expression, 1)], implicitRowMappers,
                disambiguateVariableNames: disambiguate);
          }
        })
        .expand((expressions) => expressions)
        .toList();
  }
}
