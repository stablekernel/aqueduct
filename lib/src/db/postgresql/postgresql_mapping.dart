import 'package:postgres/postgres.dart';
import '../db.dart';
import '../query/mixin.dart';

class PostgresNamer implements QueryMatcherTranslator {
  Map<ManagedEntity, Map<ManagedPropertyDescription, String>> tableAliases = {};
  void addAliasForEntity(ManagedEntity e, {ManagedPropertyDescription fromProperty}) {
    var count = tableAliases.length;
    var aliasName = "t$count";

    var inner = tableAliases[e] ?? {};
    inner[fromProperty] = aliasName;
    tableAliases[e] = inner;
  }
  String tableReferenceForEntity(ManagedEntity e, {ManagedPropertyDescription fromProperty}) {
    var entityAliases = tableAliases[e] ?? {};
    return entityAliases[fromProperty] ?? e.tableName;
  }
  String tableDefinitionForEntity(ManagedEntity e, {ManagedPropertyDescription fromProperty}) {
    var tableName = e.tableName;
    var entityAliases = tableAliases[e];
    if (entityAliases == null) {
      return tableName;
    }

    var alias = entityAliases[fromProperty];
    if (alias == null) {
      return tableName;
    }

    return "$tableName $alias";
  }

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

  String typeSuffixForProperty(ManagedPropertyDescription desc) {
    var type = PostgreSQLFormat.dataTypeStringForDataType(typeMap[desc.type]);
    if (type != null) {
      return ":$type";
    }

    return "";
  }

  String columnNameForProperty(ManagedPropertyDescription desc,
      {bool withTypeSuffix: false,
      bool withTableNamespace: false,
      String withPrefix: null}) {
    var name = desc.name;
    if (desc is ManagedRelationshipDescription) {
      name = "${name}_${desc.destinationEntity.primaryKey}";
    }

    if (withTypeSuffix) {
      name = "$name${typeSuffixForProperty(desc)}";
    }

    if (withTableNamespace) {
      return "${tableReferenceForEntity(desc.entity)}.$name";
    } else if (withPrefix != null) {
      return "$withPrefix$name";
    }

    return name;
  }

  String columnNamesForProperties(Iterable<ManagedPropertyDescription> columnMappings,
      {bool withTypeSuffix: false,
      bool withTableNamespace: false,
      String withPrefix: null}) {
    return columnMappings
        .map((c) => columnNameForProperty(c,
            withTypeSuffix: withTypeSuffix,
            withTableNamespace: withTableNamespace,
            withPrefix: withPrefix))
        .join(",");
  }

  @override
  QueryPredicate comparisonPredicate(ManagedPropertyDescription desc,
      MatcherOperator operator, dynamic value) {
    var prefix = "${tableReferenceForEntity(desc.entity)}_";
    var columnName = columnNameForProperty(desc, withTableNamespace: true);
    var variableName = columnNameForProperty(desc, withPrefix: prefix);

    return new QueryPredicate(
        "$columnName ${symbolTable[operator]} @$variableName${typeSuffixForProperty(desc)}",
        {variableName: value});
  }

  @override
  QueryPredicate containsPredicate(
      ManagedPropertyDescription desc, Iterable<dynamic> values) {
    var tableName = tableReferenceForEntity(desc.entity);
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "ctns${tableName}_${counter}_";

      var variableName = columnNameForProperty(desc, withPrefix: prefix);
      tokenList.add("@$variableName${typeSuffixForProperty(desc)}");
      pairedMap[variableName] = value;

      counter++;
    });

    var columnName = columnNameForProperty(desc, withTableNamespace: true);
    return new QueryPredicate(
        "$columnName IN (${tokenList.join(",")})", pairedMap);
  }

  @override
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull) {
    var columnName = columnNameForProperty(desc, withTableNamespace: true);
    return new QueryPredicate(
        "$columnName ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  @override
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
      dynamic lhsValue, dynamic rhsValue, bool insideRange) {
    var columnName = columnNameForProperty(desc, withTableNamespace: true);
    var lhsName = columnNameForProperty(desc,
        withPrefix: "${desc.entity.tableName}_lhs_");
    var rhsName = columnNameForProperty(desc,
        withPrefix: "${desc.entity.tableName}_rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return new QueryPredicate(
        "$columnName $operation @$lhsName${typeSuffixForProperty(desc)} AND @$rhsName${typeSuffixForProperty(desc)}",
        {lhsName: lhsValue, rhsName: rhsValue});
  }

  @override
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
      StringMatcherOperator operator, dynamic value) {
    var prefix = "${tableReferenceForEntity(desc.entity)}_";
    var columnName = columnNameForProperty(desc, withTableNamespace: true);
    var variableName = columnNameForProperty(desc, withPrefix: prefix);

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
        "$columnName LIKE @$variableName${typeSuffixForProperty(desc)}",
        {variableName: matchValue});
  }
}

enum PersistentJoinType { leftOuter }

ManagedPropertyDescription propertyForName(
    ManagedEntity entity, String propertyName) {
  var property = entity.properties[propertyName];

  if (property == null) {
    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
        "Property $propertyName does not exist on ${entity.tableName}");
  }

  if (property is ManagedRelationshipDescription &&
      property.relationshipType != ManagedRelationshipType.belongsTo) {
    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
        "Property '$propertyName' is a hasMany or hasOne relationship and is invalid as a result property of "
            "'${entity.tableName}', use one of the join methods in 'Query<T>' instead.");
  }

  return property;
}

List<PropertyToColumnMapper> mappersForKeys(
    ManagedEntity entity, List<String> keys) {
  var primaryKeyIndex = keys.indexOf(entity.primaryKey);
  if (primaryKeyIndex == -1) {
    keys.insert(0, entity.primaryKey);
  } else if (primaryKeyIndex > 0) {
    keys.removeAt(primaryKeyIndex);
    keys.insert(0, entity.primaryKey);
  }

  return keys
      .map((key) => new PropertyToColumnMapper(propertyForName(entity, key)))
      .toList();
}

class PropertyToColumnMapper {
  PropertyToColumnMapper(this.property);

  ManagedPropertyDescription property;
  String get name => property.name;

  String toString() {
    return "Mapper on $property";
  }
}

class PropertyToRowMapper extends PropertyToColumnMapper {
  PropertyToRowMapper(this.type, ManagedPropertyDescription property, this.orderedMappingElements, {this.explicitPredicate, this.where})
      : super(property) {}

  PersistentJoinType type;
  ManagedObject where;
  QueryPredicate explicitPredicate;
  List<PropertyToColumnMapper> orderedMappingElements;

  String get name {
    ManagedRelationshipDescription p = property;
    return "${p.name}_${p.destinationEntity.primaryKey}";
  }

  ManagedPropertyDescription get joinProperty =>
      (property as ManagedRelationshipDescription).inverseRelationship;

  List<PropertyToColumnMapper> get flattened {
    return orderedMappingElements.expand((c) {
      if (c is PropertyToRowMapper) {
        return c.flattened;
      }
      return [c];
    }).toList();
  }

  List<PropertyToRowMapper> get orderedNestedRowMappings {
    return orderedMappingElements
        .where((e) => e is PropertyToRowMapper)
        .expand((e) {
      var a = [e];
      a.addAll((e as PropertyToRowMapper).orderedNestedRowMappings);
      return a;
    }).toList();
  }

  bool get isToMany {
    var rel = property as ManagedRelationshipDescription;

    return rel.relationshipType == ManagedRelationshipType.hasMany;
  }

  bool representsSameJoinAs(PropertyToRowMapper other) {
    ManagedRelationshipDescription thisProperty = property;
    ManagedRelationshipDescription otherProperty = other.property;

    return thisProperty.destinationEntity == otherProperty.destinationEntity &&
        thisProperty.entity == otherProperty.entity &&
        thisProperty.name == otherProperty.name;
  }
}
