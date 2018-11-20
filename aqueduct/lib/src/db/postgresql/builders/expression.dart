import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/table.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/managed/key_path.dart';

class ColumnExpressionBuilder {
  QueryExpression queryExpression;
  PredicateExpression predicateExpression;
  TableBuilder _table;
  List<TableBuilder> tables;
  ManagedPropertyDescription explicitProperty;
  bool areTablesLinked = false;

  ColumnExpressionBuilder(this._table, this.queryExpression, {this.explicitProperty});
  ColumnExpressionBuilder.property(this._table, this.predicateExpression, this.explicitProperty);

  QueryPredicate get predicate {
    finalize();
    return _getPredicate(queryExpression: queryExpression,
        predicateExpression: predicateExpression,
        property: explicitProperty);
  }

  void finalize() {
    // this will discover all joined tables and ensure all necessary table aliases are created
    tables = _tables;
  }

  List<TableBuilder> get _tables {
    final tables = [_table];

    if (queryExpression != null) {
      tables.addAll(_getTablesFromQuery(queryExpression, _table));
    }

    return tables;
  }

  List<TableBuilder> _getTablesFromQuery(QueryExpression queryExpression, TableBuilder table) {
    final predicateExpression = queryExpression.expression;
    List<TableBuilder> tables = [];

    if (predicateExpression is LogicalOperantNode<QueryExpression>) {
      final expr = predicateExpression as LogicalOperantNode<QueryExpression>;
      tables.addAll(_getTablesFromQuery(expr.operand, table));
      tables.addAll(_getTablesFromQuery(expr.operand2, table));
    } else {
      final keyPath = queryExpression.keyPath;
      final derivedTable = _isOnJoinedTable(keyPath) ? _findJoinedTable(_table, keyPath) : _table;
      final derivedProperty = _getProperty(keyPath);
      tables.add(ColumnExpressionConcrete(derivedTable, predicateExpression, derivedProperty).table);
    }

    return tables;
  }

  QueryPredicate _getPredicate({QueryExpression queryExpression, PredicateExpression predicateExpression, ManagedPropertyDescription property}) {
    final explicitPredicate = (predicateExpression != null &&
        property != null)
        ? _getExplicitPredicate(predicateExpression, property)
        : QueryPredicate.empty();

    final predicateFromQuery = queryExpression != null
        ? _getPredicateFromQuery(queryExpression)
        : QueryPredicate.empty();

    return QueryPredicate.and([explicitPredicate, predicateFromQuery]);
  }

  QueryPredicate _getExplicitPredicate(PredicateExpression predicateExpression, ManagedPropertyDescription property) {
    if (predicateExpression is LogicalOperantNode<QueryExpression>) {
      final node = predicateExpression as LogicalOperantNode<QueryExpression>;
      return _getPredicateFromNode(node);
    } else {
      return _getPredicateFromLeaf(predicateExpression, property: property);
    }
  }

  QueryPredicate _getPredicateFromQuery(QueryExpression queryExpression) {
    final predicateExpression = queryExpression.expression;

    if (predicateExpression is LogicalOperantNode<QueryExpression>) {
      final node = predicateExpression as LogicalOperantNode<QueryExpression>;
      return _getPredicateFromNode(node);
    } else {
      return _getPredicateFromLeaf(predicateExpression, keyPath: queryExpression.keyPath);
    }
  }

  QueryPredicate _getPredicateFromNode(LogicalOperantNode<QueryExpression> expression) {
    final lhs = _getPredicate(queryExpression: expression.operand);
    final rhs = _getPredicate(queryExpression: expression.operand2);

    if (expression is AndExpression<QueryExpression>) {
      return QueryPredicate.and([lhs, rhs], isGrouped: expression.isGrouped);
    } else if (expression is OrExpression<QueryExpression>) {
      return QueryPredicate.or([lhs, rhs], isGrouped: expression.isGrouped);
    }
  }

  QueryPredicate _getPredicateFromLeaf(PredicateExpression predicateExpression, {ManagedPropertyDescription property, KeyPath keyPath}) {
    if (property == null && keyPath == null) {
      throw "You must provide either a property or a keypath with which to derive a property";
    }

    ColumnExpressionConcrete columnExpression;

    if (property != null) {
      columnExpression = ColumnExpressionConcrete(_table, predicateExpression, property);
    } else {
      final derivedTable = _isOnJoinedTable(keyPath) ? _findJoinedTable(_table, keyPath) : _table;
      final derivedProperty = _getProperty(keyPath);
      columnExpression = ColumnExpressionConcrete(derivedTable, predicateExpression, derivedProperty);
    }

    if (predicateExpression is ComparisonExpression) {
      return columnExpression.comparisonPredicate(predicateExpression.operant, predicateExpression.operand);
    } else if (predicateExpression is RangeExpression) {
      return columnExpression.rangePredicate(predicateExpression.operand, predicateExpression.operand2, insideRange: predicateExpression.operant == RangeOperant.between);
    } else if (predicateExpression is NullCheckExpression) {
      return columnExpression.nullPredicate(isNull: predicateExpression.operand);
    } else if (predicateExpression is SetMembershipExpression) {
      return columnExpression.containsPredicate(predicateExpression.operand, within: predicateExpression.within);
    } else if (predicateExpression is StringExpression) {
      return columnExpression.stringPredicate(
          predicateExpression.operator, predicateExpression.operand,
          caseSensitive: predicateExpression.caseSensitive,
          invertOperator: predicateExpression.invertOperator
      );
    }

    throw UnsupportedError(
        "Unknown expression applied to 'Query'. '${predicateExpression.runtimeType}' is not supported by 'PostgreSQL'.");
  }

  bool _isOnJoinedTable(KeyPath keyPath) {
    final firstElement = keyPath.path.first;
    final lastElement = keyPath.path.last;

    bool isPropertyOnThisEntity = keyPath.length == 1;
    bool isForeignKey = keyPath.length == 2 &&
        lastElement is ManagedAttributeDescription &&
        lastElement.isPrimaryKey &&
        firstElement is ManagedRelationshipDescription &&
        firstElement.isBelongsTo;
    bool isBelongsTo = lastElement is ManagedRelationshipDescription &&
        lastElement.isBelongsTo;
    bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

    return (
        !((isPropertyOnThisEntity && isColumn) || isForeignKey) // TODO: further understand why these checks mean the property is on another table and decmopose into named variables
        && !(keyPath.length == 0
            || (keyPath.length == 1 && keyPath[0] is! ManagedRelationshipDescription))
    );
  }

  TableBuilder _findJoinedTable(TableBuilder table, KeyPath keyPath) {
    // creates & joins a TableBuilder for any relationship in keyPath
    // if it doesn't exist.
    if (keyPath.length == 0) {
      return table;
    } else if (keyPath.length == 1 && keyPath[0] is! ManagedRelationshipDescription) {
      return table;
    } else {
      final ManagedRelationshipDescription head = keyPath[0];
      TableBuilder join = table.returning
          .whereType<TableBuilder>()
          .firstWhere((m) => m.isJoinOnProperty(head), orElse: () => null);
      if (join == null) {
        join = TableBuilder.implicit(table, head);
        table.addJoinTableBuilder(join);
      }
      return _findJoinedTable(join, KeyPath.byRemovingFirstNKeys(keyPath, 1));
    }
  }

  ManagedPropertyDescription _getProperty(KeyPath keyPath) {
    final firstElement = keyPath.path.first;
    final lastElement = keyPath.path.last;

    bool isPropertyOnThisEntity = keyPath.length == 1;
    bool isForeignKey = keyPath.length == 2 &&
        lastElement is ManagedAttributeDescription &&
        lastElement.isPrimaryKey &&
        firstElement is ManagedRelationshipDescription &&
        firstElement.isBelongsTo;
    bool isBelongsTo = lastElement is ManagedRelationshipDescription &&
        lastElement.isBelongsTo;
    bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

    if (isPropertyOnThisEntity && isColumn) {
      // This will occur if we selected a column.
      return lastElement;
    } else if (isForeignKey) {
      // This will occur if we selected a belongs to relationship or a belongs to relationship's
      // primary key. In either case, this is a column in this table (a foreign key column).
      return firstElement;
    } else if (lastElement is ManagedRelationshipDescription) {
      final inversePrimaryKey = lastElement.inverse.entity.primaryKeyAttribute;
      return inversePrimaryKey;
    } else {
      return lastElement;
    }
  }
}

class ColumnExpressionConcrete extends ColumnBuilder {
  ColumnExpressionConcrete(TableBuilder table, this.expression, ManagedPropertyDescription property) :
      super(table, property);

  PredicateExpression expression;

  String get defaultPrefix => "$prefix${table.sqlTableReference}_";

  String get prefix => table.tableAlias != null ? table.tableAlias : "";

  QueryPredicate comparisonPredicate(
      ComparisonOperant operator, dynamic value) {
    var name = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    return QueryPredicate(
        "$name ${ColumnBuilder.symbolTable[operator]} @$variableName$sqlTypeSuffix",
        {variableName: convertValueForStorage(value)});
  }

  QueryPredicate containsPredicate(Iterable<dynamic> values,
      {bool within = true}) {
    var tokenList = [];
    var pairedMap = <String, dynamic>{};

    var counter = 0;
    values.forEach((value) {
      var prefix = "$defaultPrefix${counter}_";

      var variableName = sqlColumnName(withPrefix: prefix);
      tokenList.add("@$variableName$sqlTypeSuffix");
      pairedMap[variableName] = convertValueForStorage(value);

      counter++;
    });

    var name = sqlColumnName(withTableNamespace: true);
    var keyword = within ? "IN" : "NOT IN";
    return QueryPredicate("$name $keyword (${tokenList.join(",")})", pairedMap);
  }

  QueryPredicate nullPredicate({bool isNull = true}) {
    var name = sqlColumnName(withTableNamespace: true);
    return QueryPredicate("$name ${isNull ? "ISNULL" : "NOTNULL"}", {});
  }

  QueryPredicate rangePredicate(dynamic lhsValue, dynamic rhsValue,
      {bool insideRange = true}) {
    var name = sqlColumnName(withTableNamespace: true);
    var lhsName = sqlColumnName(withPrefix: "${defaultPrefix}lhs_");
    var rhsName = sqlColumnName(withPrefix: "${defaultPrefix}rhs_");
    var operation = insideRange ? "BETWEEN" : "NOT BETWEEN";

    return QueryPredicate(
        "$name $operation @$lhsName$sqlTypeSuffix AND @$rhsName$sqlTypeSuffix",
        {
          lhsName: convertValueForStorage(lhsValue),
          rhsName: convertValueForStorage(rhsValue)
        });
  }

  QueryPredicate stringPredicate(
      StringComparisonOperant operator, dynamic value,
      {bool caseSensitive = true, bool invertOperator = false}) {
    var n = sqlColumnName(withTableNamespace: true);
    var variableName = sqlColumnName(withPrefix: defaultPrefix);

    var matchValue = value;
    var operation = caseSensitive ? "LIKE" : "ILIKE";
    if (invertOperator) {
      operation = "NOT $operation";
    }
    switch (operator) {
      case StringComparisonOperant.beginsWith:
        matchValue = "$value%";
        break;
      case StringComparisonOperant.endsWith:
        matchValue = "%$value";
        break;
      case StringComparisonOperant.contains:
        matchValue = "%$value%";
        break;
      default:
        break;
    }

    return QueryPredicate("$n $operation @$variableName$sqlTypeSuffix",
        {variableName: matchValue});
  }
}
