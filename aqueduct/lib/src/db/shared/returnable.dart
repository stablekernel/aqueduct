import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/shared/builders/expression.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';

abstract class Returnable {}

abstract class DbWrapper {
  String suffix(ManagedPropertyDescription property);

/// 数据库类型名称，比如:postgresql,mysql等
  String get sqlName;

  ColumnExpressionBuilder getColumnExpressionBuilder(TableBuilder table,
      ManagedPropertyDescription property, PredicateExpression expression,
      {String prefix = ""});
}
