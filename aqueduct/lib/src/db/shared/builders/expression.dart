import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:aqueduct/src/db/shared/builders/column.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';

abstract class ColumnExpressionBuilder extends ColumnBuilder {
  ColumnExpressionBuilder(DbWrapper dbWrapper, TableBuilder table,
      ManagedPropertyDescription property, this.expression,
      {this.prefix = ""})
      : super(dbWrapper, table, property);

  final String prefix;
  PredicateExpression expression;

  String get defaultPrefix => "$prefix${table.sqlTableReference}_";

  QueryPredicate get predicate {
    final expr = expression;
    if (expr is ComparisonExpression) {
      return comparisonPredicate(expr.operator, expr.value);
    } else if (expr is RangeExpression) {
      return rangePredicate(expr.lhs, expr.rhs, insideRange: expr.within);
    } else if (expr is NullCheckExpression) {
      return nullPredicate(isNull: expr.shouldBeNull);
    } else if (expr is SetMembershipExpression) {
      return containsPredicate(expr.values, within: expr.within);
    } else if (expr is StringExpression) {
      return stringPredicate(expr.operator, expr.value,
          caseSensitive: expr.caseSensitive,
          invertOperator: expr.invertOperator,
          allowSpecialCharacters: expr.allowSpecialCharacters);
    }

    throw UnsupportedError(
        "Unknown expression applied to 'Query'. '${expr.runtimeType}' is not supported by '${dbWrapper?.sqlName}'.");
  }

  QueryPredicate comparisonPredicate(PredicateOperator operator, dynamic value);

  QueryPredicate containsPredicate(Iterable<dynamic> values,
      {bool within = true});

  QueryPredicate nullPredicate({bool isNull = true});

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue,
      {bool insideRange = true});

  QueryPredicate stringPredicate(PredicateStringOperator operator, String value,
      {bool caseSensitive = true,
      bool invertOperator = false,
      bool allowSpecialCharacters = true});

  String escapeLikeString(String input) {
    return input.replaceAllMapped(
        RegExp(r"(\\|%|_)"), (Match m) => "\\${m[0]}");
  }
}
