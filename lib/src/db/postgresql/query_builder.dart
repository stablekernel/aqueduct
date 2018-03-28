import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/postgresql/builders/value.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';

import '../db.dart';
import 'row_instantiator.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

class PostgresQueryBuilder extends TableBuilder {
  PostgresQueryBuilder(PostgresQuery query) : super(query) {
    (query.valueMap ?? query.values?.backing?.contents).forEach((key, value) {
      addColumnValueBuilder(key, value);
    });

    columnValueBuilders.forEach((cv) {
      variables[cv.sqlColumnName(withPrefix: valueKeyPrefix)] = cv.value;
    });

    finalize(variables);
  }

  static const String valueKeyPrefix = "v_";

  final Map<String, dynamic> variables = {};

  final List<ColumnValueBuilder> columnValueBuilders = [];

  bool get containsJoins => returning.reversed.any((p) => p is TableBuilder);

  String get sqlWhereClause {
    if (predicate?.format == null) {
      return null;
    }
    if (predicate.format.isEmpty) {
      return null;
    }
    return predicate.format;
  }

  void addColumnValueBuilder(String key, dynamic value) {
    final builder = _createColumnValueBuilder(key, value);
    columnValueBuilders.add(builder);
    variables[builder.sqlColumnName(withPrefix: valueKeyPrefix)] = builder.value;
  }

  List<ManagedObject> instancesForRows(List<List<dynamic>> rows) {
    final instantiator = new RowInstantiator(this, returning);
    return instantiator.instancesForRows(rows);
  }

  ColumnValueBuilder _createColumnValueBuilder(String key, dynamic value) {
    var property = entity.properties[key];
    if (property == null) {
      throw new ArgumentError("Invalid query. Column '$key' does "
          "not exist for table '${entity.tableName}'");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return new ColumnValueBuilder(this, property, value[property.destinationEntity.primaryKey]);
        }

        throw new ArgumentError("Invalid query. Column '$key' in "
            "'${entity.tableName}' does not exist. '$key' recognized as ORM relationship. "
            "Provided value must be 'Map' or ${property.destinationEntity.name}.");
      }
    }

    return new ColumnValueBuilder(this, property, value);
  }

  /*
      Methods that return portions of a SQL statement for this object
   */

  String get sqlColumnsAndValuesToUpdate {
    return columnValueBuilders.map((m) {
      final columnName = m.sqlColumnName();
      final variableName = m.sqlColumnName(withPrefix: "@$valueKeyPrefix", withTypeSuffix: true);
      return "$columnName=$variableName";
    }).join(",");
  }

  String get sqlColumnsToInsert {
    return columnValueBuilders.map((c) => c.sqlColumnName()).join(",");
  }

  String get sqlValuesToInsert {
    return columnValueBuilders.map((c) => c.sqlColumnName(withTypeSuffix: true, withPrefix: "@$valueKeyPrefix")).join(",");
  }

  String get sqlColumnsToReturn {
    return flattenedColumnsToReturn.map((p) => p.sqlColumnName(withTableNamespace: containsJoins)).join(",");
  }

  String get sqlOrderBy {
    var allSorts = new List<ColumnSortBuilder>.from(columnSortBuilders);

    var nestedSorts = returning.where((m) => m is TableBuilder).expand((m) => (m as TableBuilder).columnSortBuilders);
    allSorts.addAll(nestedSorts);

    if (allSorts.length == 0) {
      return "";
    }

    return "ORDER BY ${allSorts.map((s) => s.sqlOrderBy).join(",")}";
  }
}
