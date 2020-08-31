
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/shared/returnable.dart';
import 'package:aqueduct/src/db/shared/builders/column.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';
class ColumnSortBuilder extends ColumnBuilder {
  ColumnSortBuilder(DbWrapper dbWrapper, TableBuilder table, String key, QuerySortOrder order)
      : order = order == QuerySortOrder.ascending ? "ASC" : "DESC",
        super(dbWrapper,table, table.entity.properties[key]);

  final String order;

  String get sqlOrderBy => "${sqlColumnName(withTableNamespace: true)} $order";
}
