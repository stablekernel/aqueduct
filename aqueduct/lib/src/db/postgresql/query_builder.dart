import 'package:aqueduct/src/db/managed/relationship_type.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/postgresql/builders/value.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';

import '../db.dart';
import 'row_instantiator.dart';

class PostgresQueryBuilder extends TableBuilder {
  PostgresQueryBuilder(PostgresQuery query, [String prefixIndex = ""])
      : valueKeyPrefix = "v${prefixIndex}_",
        placeholderKeyPrefix = "@v${prefixIndex}_",
        super(query) {
    (query.valueMap ?? query.values?.backing?.contents)
        .forEach(addColumnValueBuilder);

    finalize(variables);
  }

  final String valueKeyPrefix;
  final String placeholderKeyPrefix;

  final Map<String, dynamic> variables = {};

  final Map<String, ColumnValueBuilder> columnValueBuildersByKey = {};

  Iterable<String> get columnValueKeys =>
      columnValueBuildersByKey.keys.toList().reversed;

  Iterable<ColumnValueBuilder> get columnValueBuilders =>
      columnValueBuildersByKey.values;

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
    columnValueBuildersByKey[builder.sqlColumnName()] = builder;
    variables[builder.sqlColumnName(withPrefix: valueKeyPrefix)] =
        builder.value;
  }

  List<T> instancesForRows<T extends ManagedObject>(List<List<dynamic>> rows) {
    final instantiator = RowInstantiator(this, returning);
    return instantiator.instancesForRows<T>(rows);
  }

  ColumnValueBuilder _createColumnValueBuilder(String key, dynamic value) {
    var property = entity.properties[key];
    if (property == null) {
      throw ArgumentError("Invalid query. Column '$key' does "
          "not exist for table '${entity.tableName}'");
    }

    if (property is ManagedRelationshipDescription) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        return null;
      }

      if (value != null) {
        if (value is ManagedObject || value is Map) {
          return ColumnValueBuilder(
              this, property, value[property.destinationEntity.primaryKey]);
        }

        throw ArgumentError("Invalid query. Column '$key' in "
            "'${entity.tableName}' does not exist. '$key' recognized as ORM relationship. "
            "Provided value must be 'Map' or ${property.destinationEntity.name}.");
      }
    }

    return ColumnValueBuilder(this, property, value);
  }

  /*
      Methods that return portions of a SQL statement for this object
   */

  String get sqlColumnsAndValuesToUpdate {
    return columnValueBuilders.map((m) {
      final columnName = m.sqlColumnName();
      final variableName = m.sqlColumnName(
        withPrefix: placeholderKeyPrefix,
        withTypeSuffix: true,
      );
      return "$columnName=$variableName";
    }).join(",");
  }

  String get sqlColumnsToInsert => columnValueKeys.join(",");

  String get sqlValuesToInsert => valuesToInsert(columnValueKeys);

  String valuesToInsert(Iterable<String> forKeys) {
    if (forKeys.isEmpty) {
      return "DEFAULT";
    }
    return forKeys.map(_valueToInsert).join(",");
  }

  String _valueToInsert(String key) {
    final builder = columnValueBuildersByKey[key];
    if (builder == null) {
      return "DEFAULT";
    }

    return builder.sqlColumnName(
      withTypeSuffix: true,
      withPrefix: placeholderKeyPrefix,
    );
  }

  String get sqlColumnsToReturn {
    return flattenedColumnsToReturn
        .map((p) => p.sqlColumnName(withTableNamespace: containsJoins))
        .join(",");
  }

  String get sqlOrderBy {
    var allSorts = List<ColumnSortBuilder>.from(columnSortBuilders);

    var nestedSorts =
        returning.whereType<TableBuilder>().expand((m) => m.columnSortBuilders);
    allSorts.addAll(nestedSorts);

    if (allSorts.isEmpty) {
      return "";
    }

    return "ORDER BY ${allSorts.map((s) => s.sqlOrderBy).join(",")}";
  }
}
