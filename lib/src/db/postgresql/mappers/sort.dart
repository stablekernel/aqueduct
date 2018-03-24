import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/query/query.dart';

class SortMapper extends ColumnMapper {
  SortMapper(TableMapper table, ManagedPropertyDescription property, QuerySortOrder order)
      : super(table, property) {
    this.order = (order == QuerySortOrder.ascending ? "ASC" : "DESC");
  }

  String order;

  String get orderByString => "${columnName(withTableNamespace: true)} $order";
}
