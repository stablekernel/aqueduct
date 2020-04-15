import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/mysql/mysql_dbwrapper.dart';
import 'package:aqueduct/src/db/mysql/mysql_query.dart';
import 'package:aqueduct/src/db/mysql/row_instantiator.dart';
import 'package:aqueduct/src/db/shared/builders/sort.dart';
import 'package:aqueduct/src/db/shared/builders/table.dart';
import 'package:aqueduct/src/db/shared/builders/value.dart';
import 'package:sqljocky5/sqljocky.dart';


class MySqlQueryBuilder extends TableBuilder {
  MySqlQueryBuilder(MySqlQuery query) : super(query,dbWrapper:MySqlDbWrapper()) {
    (query.valueMap ?? query.values?.backing?.contents)
        .forEach(addColumnValueBuilder);

    columnValueBuilders.forEach((cv) {
      variables[cv.sqlColumnName(withPrefix: valueKeyPrefix)] = cv.value;
    });

    finalize(variables);
  }

  static const String valueKeyPrefix = "v_";

  final Map<String, dynamic> variables = {};

  final List<ColumnValueBuilder> columnValueBuilders = [];

  bool get containsJoins =>
      returning.reversed.any((p) => p is TableBuilder);

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
    variables[builder.sqlColumnName(withPrefix: valueKeyPrefix)] =
        builder.value;
  }

  List<T> instancesForRows<T extends ManagedObject>(List<Row> rows) {
    final instantiator = MySqlRowInstantiator(this, returning);
    return instantiator.instancesForRows<T>(rows);
  }

  ColumnValueBuilder _createColumnValueBuilder(
      String key, dynamic value) {
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
          return ColumnValueBuilder(dbWrapper,
              this, property, value[property.destinationEntity.primaryKey]);
        }

        throw ArgumentError("Invalid query. Column '$key' in "
            "'${entity.tableName}' does not exist. '$key' recognized as ORM relationship. "
            "Provided value must be 'Map' or ${property.destinationEntity.name}.");
      }
    }

    return ColumnValueBuilder(dbWrapper, this, property, value);
  }

  /*
      Methods that return portions of a SQL statement for this object
   */

  String get sqlColumnsAndValuesToUpdate {
    return columnValueBuilders.where((c) => !c.property.autoincrement).map((m) {
      final columnName = m.sqlColumnName();
      final variableName = m.sqlColumnName(
        withPrefix: "$valueKeyPrefix", /* withTypeSuffix: true*/
      );
      return "$columnName=?/*$variableName*/";
    }).join(",");
  }

  String get sqlColumnsToInsert {
    return columnValueBuilders
        .where((c) => !c.property.autoincrement)
        .map((c) => "${c.sqlColumnName()}")
        .join(",");
  }

  String get sqlValuesToInsert {
    return columnValueBuilders
        .where((c) => !c.property.autoincrement)
        //  .map((c) => "?/*${c.sqlColumnName()}*/")
        .map((c) =>
            "?/*${c.sqlColumnName(withTypeSuffix: true, withPrefix: "$valueKeyPrefix")}*/")
        .join(",");
  }

  String get sqlColumnsToReturn {
    return flattenedColumnsToReturn
        .map((p) => "${p.sqlColumnName(withTableNamespace: containsJoins)}")
        .join(",");
  }

  String get sqlOrderBy {
    var allSorts = List<ColumnSortBuilder>.from(columnSortBuilders);

    var nestedSorts = returning
        .whereType<TableBuilder>()
        .expand((m) => m.columnSortBuilders);
    allSorts.addAll(nestedSorts);

    if (allSorts.isEmpty) {
      return "";
    }
    return "ORDER BY ${allSorts.map((s) => s.sqlOrderBy).join(",")}";
  }
}
