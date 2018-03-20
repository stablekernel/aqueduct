import 'package:aqueduct/src/db/managed/key_path.dart';

import '../db.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/postgresql/mappers/expression.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/row.dart';

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
      List<QueryExpression<dynamic, dynamic>> expressions, List<RowMapper> implicitRowMappers,
      {bool disambiguateVariableNames: false}) {
    if (expressions == null) {
      return [];
    }

    var prefix = disambiguateVariableNames ? "implicit_" : "";

    return expressions
        .map((expression) {
          final firstElement = expression.keyPath.path.first;
          final lastElement = expression.keyPath.path.last;

          bool isPropertyOnThisEntity = expression.keyPath.length == 1;
          bool isForeignKey =
              expression.keyPath.length == 2 && lastElement is ManagedAttributeDescription && lastElement.isPrimaryKey
                  && firstElement is ManagedRelationshipDescription && firstElement.isBelongsTo;

          if (isPropertyOnThisEntity) {
            bool isBelongsTo = lastElement is ManagedRelationshipDescription && lastElement.isBelongsTo;
            bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

            if (isColumn) {
              return [new ExpressionMapper(this, lastElement, expression.expression, additionalVariablePrefix: prefix)];
            }
          } else if (isForeignKey) {
            return [
              new ExpressionMapper(this, expression.keyPath.path.first, expression.expression,
                  additionalVariablePrefix: prefix)
            ];
          }

          // If we fall thru to here, then we're either referencing a has-a relationship property
          // directly or we have a key-path that we need to further traverse.
          // We'll either create an implicit join on the table, or if we're already joining on that table,
          // we'll make sure to use that joined table.

          bool disambiguate = true;

          // Let's see if we already have a join for this relationship
          // and if not, create an implicit one.
          RowMapper rowMapper = returningOrderedMappers
              .where((m) => m is RowMapper)
              .firstWhere((m) => (m as RowMapper).isJoinOnProperty(firstElement), orElse: () {
            disambiguate = false;

            final m = new RowMapper.implicit(PersistentJoinType.leftOuter, firstElement, this);
            implicitRowMappers.add(m);
            return m;
          });

          // Then build the expression relative to the joined table
          // If we have accessed a property of this property, we'll duplicate the expression object and lop off the key path
          // so that it can be resolved relative to the joined table. Otherwise, do the same but add a primary key instead of remove it.
          if (isPropertyOnThisEntity) {
            final inversePrimaryKey = (lastElement as ManagedRelationshipDescription).inverse.entity.primaryKeyAttribute;
            final expr = new QueryExpression(new KeyPath(inversePrimaryKey))
              ..expression = expression.expression;
            return rowMapper.propertyExpressionsFromObject([expr], implicitRowMappers,
                disambiguateVariableNames: disambiguate);
          }

          return rowMapper.propertyExpressionsFromObject([new QueryExpression.forNestedProperty(expression, 1)], implicitRowMappers,
              disambiguateVariableNames: disambiguate);
        })
        .expand((expressions) => expressions)
        .toList();
  }
}
