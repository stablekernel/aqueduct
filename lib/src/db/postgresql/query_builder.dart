import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/postgresql/builders/value.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';

import '../db.dart';
import 'row_instantiator.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

class PostgresQueryBuilder extends TableBuilder {
  static const String valueKeyPrefix = "v_";

  PostgresQueryBuilder(PostgresQuery query) : super(query) {
    (query.valueMap ?? query.values?.backing?.contents).forEach((key, value) {
      addColumnValueBuilder(key, value);
    });

    columnValueMappers.forEach((cv) {
      variables[cv.columnName(withPrefix: valueKeyPrefix)] = cv.value;
    });
    finalize(variables);
  }

  final Map<String, dynamic> variables = {};

  final List<ColumnValueBuilder> columnValueMappers = [];

  bool get containsJoins => returning.reversed.any((p) => p is TableBuilder);

  void addColumnValueBuilder(String key, dynamic value) {
    final builder = _createColumnValueBuilder(key, value);
    columnValueMappers.add(builder);
    variables[builder.columnName(withPrefix: valueKeyPrefix)] = builder.value;
  }

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    final instantiator = new RowInstantiator(this, returning);
    return instantiator.instancesForRows(rows);
  }

  String get whereClauseString => predicate?.format;

  String get updateValueString {
    return columnValueMappers.map((m) {
      var columnName = m.columnName();
      var variableName = m.columnName(withPrefix: "@$valueKeyPrefix", withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get valuesColumnString {
    return columnValueMappers.map((c) => c.columnName()).join(",");
  }

  String get insertionValueString {
    return columnValueMappers.map((c) => c.columnName(withTypeSuffix: true, withPrefix: "@$valueKeyPrefix")).join(",");
  }

  @override
  String get joinString {
    return returning.where((e) => e is TableBuilder).map((e) => (e as TableBuilder).joinString).join(" ");
  }

  String get returningColumnString {
    return returningFlattened.map((p) => p.columnName(withTableNamespace: containsJoins)).join(",");
  }

  String get orderByString {
    var allSortMappers = new List<ColumnSortBuilder>.from(columnSortBuilders);

    var nestedSorts =
        returning.where((m) => m is TableBuilder).expand((m) => (m as TableBuilder).columnSortBuilders);
    allSortMappers.addAll(nestedSorts);

    if (allSortMappers.length == 0) {
      return "";
    }

    return "ORDER BY ${allSortMappers.map((s) => s.orderByString).join(",")}";
  }

  ColumnValueBuilder _createColumnValueBuilder(String key, dynamic value) {
    var property = entity.properties[key];
    if (property == null) {
      throw new ArgumentError("Invalid query. Column '$key' does not exist for table '${entity.tableName}'");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return new ColumnValueBuilder(this, property, value[property.destinationEntity.primaryKey]);
        }

        throw new ArgumentError("Invalid query. Column '$key' in '${entity.tableName}' does not exist. "
            "'$key' recognized as ORM relationship. Provided value must be 'Map' "
            "or ${property.destinationEntity.name}.");
      }
    }

    return new ColumnValueBuilder(this, property, value);
  }
}
