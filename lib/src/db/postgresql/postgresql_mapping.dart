import 'package:postgres/postgres.dart';
import '../db.dart';
import '../query/mixin.dart';

class PostgresMapper implements QueryMatcherTranslator {
  Map<MatcherOperator, String> symbolTable = {
    MatcherOperator.lessThan: "<",
    MatcherOperator.greaterThan: ">",
    MatcherOperator.notEqual: "!=",
    MatcherOperator.lessThanEqualTo: "<=",
    MatcherOperator.greaterThanEqualTo: ">=",
    MatcherOperator.equalTo: "="
  };

  Map<ManagedPropertyType, PostgreSQLDataType> typeMap = {
    ManagedPropertyType.integer: PostgreSQLDataType.integer,
    ManagedPropertyType.bigInteger: PostgreSQLDataType.bigInteger,
    ManagedPropertyType.string: PostgreSQLDataType.text,
    ManagedPropertyType.datetime: PostgreSQLDataType.timestampWithoutTimezone,
    ManagedPropertyType.boolean: PostgreSQLDataType.boolean,
    ManagedPropertyType.doublePrecision: PostgreSQLDataType.double
  };

  String stringForJoinType(PersistentJoinType t) {
    switch (t) {
      case PersistentJoinType.leftOuter:
        return "LEFT OUTER";
    }
    return null;
  }

  String typeSuffix(ManagedPropertyDescription desc) {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[desc.type]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  String columnNameForProperty(ManagedPropertyDescription desc,
      {bool typed: false, bool includeTableName: false, String prefix: null}) {
    var name = desc.name;
    if (desc is ManagedRelationshipDescription) {
      name = "${name}_${desc.destinationEntity.primaryKey}";
    }

    if (typed) {
      name = "$name${typeSuffix(desc)}";
    }

    if (includeTableName) {
      return "${desc.entity.tableName}.$name";
    }

    if (prefix != null) {
      name = "$prefix$name";
    }

    return name;
  }

  String columnListString(Iterable<ManagedPropertyDescription> columnMappings,
      {bool typed: false, bool includeTableName: false, String prefix: null}) {
    return columnMappings
        .map((c) => columnNameForProperty(c,
            typed: typed, includeTableName: includeTableName, prefix: prefix))
        .join(",");
  }

  @override
  QueryPredicate comparisonPredicate(ManagedPropertyDescription desc,
      MatcherOperator operator, dynamic value) {
    var prefix = "${desc.entity.tableName}_";
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var variableName = columnNameForProperty(desc, prefix: prefix);

    return new QueryPredicate(
        "$columnName ${symbolTable[operator]} @$variableName${typeSuffix(desc)}",
        {variableName: value});
  }

  @override
  QueryPredicate containsPredicate(
      ManagedPropertyDescription desc, Iterable<dynamic> values) {
    var tableName = desc.entity.tableName;
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "ctns${tableName}_${counter}_";

      var variableName = columnNameForProperty(desc, prefix: prefix);
      tokenList.add("@$variableName${typeSuffix(desc)}");
      pairedMap[variableName] = value;

      counter++;
    });

    var columnName = columnNameForProperty(desc, includeTableName: true);
    return new QueryPredicate(
        "$columnName IN (${tokenList.join(",")})", pairedMap);
  }

  @override
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull) {
    var columnName = columnNameForProperty(desc, includeTableName: true);
    return new QueryPredicate(
        "$columnName ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  @override
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
      dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var lhsName =
        columnNameForProperty(desc, prefix: "${desc.entity.tableName}_lhs_");
    var rhsName =
        columnNameForProperty(desc, prefix: "${desc.entity.tableName}_rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$columnName $operation @$lhsName${typeSuffix(desc)} AND @$rhsName${typeSuffix(desc)}",
        {lhsName: lhsValue, rhsName: rhsValue});
  }

  @override
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
      StringMatcherOperator operator, dynamic value) {
    var prefix = "${desc.entity.tableName}_";
    var columnName = columnNameForProperty(desc, includeTableName: true);
    var variableName = columnNameForProperty(desc, prefix: prefix);

    var matchValue = value;
    switch (operator) {
      case StringMatcherOperator.beginsWith:
        matchValue = "$value%";
        break;
      case StringMatcherOperator.endsWith:
        matchValue = "%$value";
        break;
      case StringMatcherOperator.contains:
        matchValue = "%$value%";
        break;
    }

    return new QueryPredicate(
        "$columnName LIKE @$variableName${typeSuffix(desc)}",
        {variableName: matchValue});
  }
}
