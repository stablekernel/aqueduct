import 'package:aqueduct/src/db/managed/property_description.dart';
import 'package:aqueduct/src/db/mysql/builders/expression.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/shared/builders/expression.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';

class MySqlDbWrapper extends DbWrapper {
  factory MySqlDbWrapper() => _singleton;
  MySqlDbWrapper._internal();
  static MySqlDbWrapper _singleton = MySqlDbWrapper._internal();

  @override
  ColumnExpressionBuilder getColumnExpressionBuilder(TableBuilder table,
      ManagedPropertyDescription property, PredicateExpression expression,
      {String prefix = ""}) {
    return MySqlColumnExpressionBuilder(this, table, property, expression,
        prefix: prefix);
  }

  @override
  String suffix(ManagedPropertyDescription property) => "";

  @override
  String get sqlName => "MySql";
}
