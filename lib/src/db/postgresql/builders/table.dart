import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';
import 'package:aqueduct/src/db/query/matcher_expression.dart';
import 'package:aqueduct/src/db/query/matcher_internal.dart';
import 'package:aqueduct/src/db/query/predicate.dart';
import 'package:aqueduct/src/db/query/query.dart';
import 'package:aqueduct/src/db/query/sort_descriptor.dart';

class TableBuilder implements Returnable {
  TableBuilder(PostgresQuery query, {this.parent, this.joinedBy}) : entity = query.entity {
    if (parent != null) {
      tableAlias = generateTableAlias();
    }
    returningValues = ColumnBuilder.fromKeys(this, query.propertiesToFetch);

    columnSortBuilders =
        query.sortDescriptors?.map((s) => new ColumnSortBuilder(this, entity.properties[s.key], s.order))?.toList() ??
            [];

    if (query.pageDescriptor != null) {
      columnSortBuilders.add(new ColumnSortBuilder(
          this, entity.attributes[query.pageDescriptor.propertyName], query.pageDescriptor.order));

      if (query.pageDescriptor.boundingValue != null) {
        final prop = entity.properties[query.pageDescriptor.propertyName];
        final operator = query.pageDescriptor.order == QuerySortOrder.ascending
            ? PredicateOperator.greaterThan
            : PredicateOperator.lessThan;
        final expr = new ColumnExpressionBuilder(
            this, prop, new ComparisonExpression(query.pageDescriptor.boundingValue, operator));
        predicates.add(expr.predicate);
      }
    }

    if (query.predicate != null) {
      predicates.add(query.predicate);
    }

    query.subQueries?.forEach((relationshipDesc, subQuery) {
      var join = new TableBuilder(subQuery, parent: this, joinedBy: relationshipDesc);

      addJoinTableBuilder(join);
    });

    addColumnExpressions(query.expressions);
  }

  TableBuilder.implicit(this.parent, this.joinedBy) : entity = joinedBy.inverse.entity {
    isImplicitlyJoined = true;
    tableAlias = generateTableAlias();
    _innerSelectColumns = [new ColumnBuilder(this, joinedBy.inverse)];
    returningValues = [];
    columnSortBuilders = [];
  }

  final ManagedEntity entity;
  final TableBuilder parent;
  final ManagedRelationshipDescription joinedBy;
  final PersistentJoinType type = PersistentJoinType.leftOuter;
  final List<QueryPredicate> predicates = [];
  List<ColumnBuilder> _innerSelectColumns;
  QueryPredicate get predicate => QueryPredicate.andPredicates(predicates);
  String tableAlias;
  List<ColumnSortBuilder> columnSortBuilders;
  List<Returnable> returningValues;
  int aliasCounter = 0;

  bool get hasImplicitJoins => returningValues.any((r) => r is TableBuilder && r.isImplicitlyJoined);
  bool isImplicitlyJoined = false;

  String get tableReferenceString => tableAlias ?? entity.tableName;

  Map<String, dynamic> get variables {
    final m = new Map.from(predicate?.parameters ?? {});
    returningValues.where((r) => r is TableBuilder).forEach((r) {
      m.addAll((r as TableBuilder).variables);
    });
    return m;
  }


  bool get isToMany {
    return joinedBy.relationshipType == ManagedRelationshipType.hasMany;
  }

  ManagedRelationshipDescription get foreignKeyProperty =>
      joinedBy.relationshipType == ManagedRelationshipType.belongsTo ? joinedBy : joinedBy.inverse;

  bool isJoinOnProperty(ManagedRelationshipDescription relationship) {
    return joinedBy.destinationEntity == relationship.destinationEntity &&
        joinedBy.entity == relationship.entity &&
        joinedBy.name == relationship.name;
  }

  String get tableNameString {
    if (tableAlias == null) {
      return entity.tableName;
    }

    return "${entity.tableName} $tableAlias";
  }

  List<ColumnBuilder> get returningColumns {
    return returningValues.fold([], (prev, c) {
      if (c is TableBuilder) {
        prev.addAll(c.returningColumns);
      } else {
        prev.add(c);
      }
      return prev;
    });
  }

  String generateTableAlias() {
    if (parent != null) {
      return parent.generateTableAlias();
    }

    tableAlias ??= "t0";
    aliasCounter++;
    return "t$aliasCounter";
  }

  void addColumnExpressions(List<QueryExpression<dynamic, dynamic>> expressions) {
    if (expressions == null) {
      return;
    }

    expressions.forEach((expression) {
      final firstElement = expression.keyPath.path.first;
      final lastElement = expression.keyPath.path.last;

      bool isPropertyOnThisEntity = expression.keyPath.length == 1;
      bool isForeignKey = expression.keyPath.length == 2 &&
          lastElement is ManagedAttributeDescription &&
          lastElement.isPrimaryKey &&
          firstElement is ManagedRelationshipDescription &&
          firstElement.isBelongsTo;

      if (isPropertyOnThisEntity) {
        bool isBelongsTo = lastElement is ManagedRelationshipDescription && lastElement.isBelongsTo;
        bool isColumn = lastElement is ManagedAttributeDescription || isBelongsTo;

        if (isColumn) {
          // This will occur if we selected a column.
          final expr = new ColumnExpressionBuilder(this, lastElement, expression.expression);
          predicates.add(expr.predicate);
          return;
        }
      } else if (isForeignKey) {
        // This will occur if we selected a belongs to relationship or a belongs to relationship's
        // primary key. In either case, this is a column in this table (a foreign key column).
        final expr = new ColumnExpressionBuilder(this, expression.keyPath.path.first, expression.expression);
        predicates.add(expr.predicate);
        return;
      }

      addColumnExpressionToJoinedTable(expression);
    });
  }

  void addColumnExpressionToJoinedTable(QueryExpression<dynamic, dynamic> expression) {
    TableBuilder joinedTable = _findJoinedTable(expression.keyPath);
    final prefix = joinedTable.isImplicitlyJoined ? "implicit_" : "";

    final lastElement = expression.keyPath.path.last;
    if (lastElement is ManagedRelationshipDescription) {
      final inversePrimaryKey = lastElement.inverse.entity.primaryKeyAttribute;
      final expr = new ColumnExpressionBuilder(joinedTable, inversePrimaryKey, expression.expression, prefix: prefix);
      joinedTable.parent.predicates.add(expr.predicate);
    } else {
      final expr = new ColumnExpressionBuilder(joinedTable, lastElement, expression.expression, prefix: prefix);
      joinedTable.parent.predicates.add(expr.predicate);
    }
  }

  TableBuilder _findJoinedTable(KeyPath keyPath) {
    // creates & joins a TableBuilder for any relationship in keyPath
    // if it doesn't exist.
    if (keyPath.length == 0) {
      return this;
    } else if (keyPath.length == 1 && keyPath[0] is! ManagedRelationshipDescription) {
      return this;
    } else {
      final head = keyPath[0];
      TableBuilder join = returningValues
          .where((r) => r is TableBuilder)
          .firstWhere((m) => (m as TableBuilder).isJoinOnProperty(head), orElse: () => null);
      if (join == null) {
        join = new TableBuilder.implicit(this, head);
        addJoinTableBuilder(join);
      }
      return join._findJoinedTable(new KeyPath.byRemovingFirstNKeys(keyPath, 1));
    }
  }

  void addJoinTableBuilder(TableBuilder r) {
    validateJoin(r);

    returningValues.add(r);

    // If we're fetching the primary key of the joined table, don't fetch
    // the foreign key from this table if it is being fetched.
    if (r.returningValues.length > 0) {
      returningValues.removeWhere((m) {
        if (m is ColumnBuilder) {
          return identical(m.property, r.joinedBy);
        }

        return false;
      });
    }

    columnSortBuilders.addAll(r.columnSortBuilders);
  }

  void validateJoin(TableBuilder table) {
    var parentTable = parent;
    while (parentTable != null) {
      var inverseMapper = parentTable.returningValues.reversed.where((pm) => pm is TableBuilder).firstWhere((pm) {
        return identical(table.joinedBy.inverse, (pm as TableBuilder).joinedBy);
      }, orElse: () => null);

      if (inverseMapper != null) {
        throw new ArgumentError("Invalid query. This query would join on the same table and foreign key twice. "
            "The offending query has a 'where' matcher on '${table.entity.tableName}.${table.joinedBy
            .name}',"
            "but this matcher should be on a parent 'Query'.");
      }

      parentTable = parentTable?.parent;
    }
  }

  QueryPredicate get joiningPredicate {
    ColumnBuilder leftMapper, rightMapper;
    if (identical(foreignKeyProperty, joinedBy)) {
      leftMapper = new ColumnBuilder(parent, joinedBy);
      rightMapper = new ColumnBuilder(this, entity.primaryKeyAttribute);
    } else {
      leftMapper = new ColumnBuilder(parent, parent.entity.primaryKeyAttribute);
      rightMapper = new ColumnBuilder(this, joinedBy.inverse);
    }

    var leftColumn = leftMapper.columnName(withTableNamespace: true);
    var rightColumn = rightMapper.columnName(withTableNamespace: true);
    return new QueryPredicate("$leftColumn=$rightColumn", null);
  }

  String get innerSelectString {
    var nestedJoins =
        returningValues.where((m) => m is TableBuilder).map((rm) => (rm as TableBuilder).joinString).join(" ");

    var flattenedColumns = returningColumns;

    var columnsWithNamespace = flattenedColumns.map((p) => p.columnName(withTableNamespace: true)).join(",");
    var columnsWithoutNamespace = flattenedColumns.map((p) => p.columnName()).join(",");

    var outerWhereString = "";
    if (predicate != null) {
      // since predicate now includes joinCondition, this creates another constraint that shouldn't exist
      outerWhereString = " WHERE ${predicate.format}";
    }

    var selectString = "SELECT $columnsWithNamespace FROM $tableNameString $nestedJoins";
    var alias = "$tableReferenceString($columnsWithoutNamespace)";
    return "LEFT OUTER JOIN ($selectString$outerWhereString) $alias ON ${joiningPredicate.format}";
  }

  String get joinString {
//    if (hasImplicitJoins) {
//      return innerSelectString;
//    }

    var totalJoinPredicate = joiningPredicate;
    if (predicates.isNotEmpty) {
      totalJoinPredicate = QueryPredicate.andPredicates([joiningPredicate, predicate]);
    }
    var thisJoin = "LEFT OUTER JOIN $tableNameString ON ${totalJoinPredicate.format}";

    if (returningValues.any((p) => p is TableBuilder)) {
      var nestedJoins = returningValues.where((p) => p is TableBuilder).map((p) {
        return (p as TableBuilder).joinString;
      }).toList();
      nestedJoins.insert(0, thisJoin);
      return nestedJoins.join(" ");
    }

    return thisJoin;
  }
}
