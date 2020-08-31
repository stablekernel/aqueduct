import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/shared/builders/column.dart';
import 'package:aqueduct/src/db/shared/builders/expression.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';

class MySqlColumnExpressionBuilder extends ColumnExpressionBuilder {
  MySqlColumnExpressionBuilder(DbWrapper dbWrapper, TableBuilder table,
      ManagedPropertyDescription property, PredicateExpression expression,
      {String prefix = ""})
      : super(dbWrapper, table, property, expression, prefix: prefix);

  @override
  QueryPredicate comparisonPredicate(
      PredicateOperator operator, dynamic value) {
    final name = sqlColumnName(withTableNamespace: true);
    final variableName = sqlColumnName(withPrefix: defaultPrefix);
    return QueryPredicate(
        "$name ${ColumnBuilder.symbolTable[operator]} ?/*$variableName$sqlTypeSuffix*/",
        {variableName: convertValueForStorage(value)});
  }

  @override
  QueryPredicate containsPredicate(Iterable<dynamic> values,
      {bool within = true}) {
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      final prefix = "$defaultPrefix${counter}_";

      final variableName = sqlColumnName(withPrefix: prefix);
      tokenList.add("?/*$variableName$sqlTypeSuffix*/");
      pairedMap[variableName] = convertValueForStorage(value);

      counter++;
    });

    final name = sqlColumnName(withTableNamespace: true);
    final keyword = within ? "IN" : "NOT IN";
    return QueryPredicate("$name $keyword (${tokenList.join(",")})", pairedMap);
  }

  @override
  QueryPredicate nullPredicate({bool isNull = true}) {
    final name = sqlColumnName(withTableNamespace: true);
    return QueryPredicate("$name ${isNull ? "IS NULL" : "IS NOT NULL"}", {});
  }

  @override
  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue,
      {bool insideRange = true}) {
    final name = sqlColumnName(withTableNamespace: true);
    final lhsName = sqlColumnName(withPrefix: "${defaultPrefix}lhs_");
    final rhsName = sqlColumnName(withPrefix: "${defaultPrefix}rhs_");
    final operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return QueryPredicate(
        "$name $operation ?/*$lhsName$sqlTypeSuffix*/ AND ?/*$rhsName$sqlTypeSuffix*/",
        {
          lhsName: convertValueForStorage(lhsValue),
          rhsName: convertValueForStorage(rhsValue)
        });
  }

  @override
  QueryPredicate stringPredicate(PredicateStringOperator operator, String value,
      {bool caseSensitive = true,
      bool invertOperator = false,
      bool allowSpecialCharacters = true}) {
    final n = sqlColumnName(withTableNamespace: true);
    final variableName = sqlColumnName(withPrefix: defaultPrefix);

    var matchValue = allowSpecialCharacters ? value : escapeLikeString(value);

    if (operator == PredicateStringOperator.equals) {
      return QueryPredicate(
          "$n = ?/*$variableName$sqlTypeSuffix*/", {variableName: matchValue});
    }

    var operation = "LIKE";//caseSensitive ? "LIKE" : "ILIKE";
    if (invertOperator) {
      operation = "NOT $operation";
    }
    switch (operator) {
      case PredicateStringOperator.beginsWith:
        matchValue = "$matchValue%";
        break;
      case PredicateStringOperator.endsWith:
        matchValue = "%$matchValue";
        break;
      case PredicateStringOperator.contains:
        matchValue = "%$matchValue%";
        break;
      default:
        break;
    }

    return QueryPredicate("$n $operation ?/*$variableName$sqlTypeSuffix*/",
        {variableName: matchValue});
  }
}
