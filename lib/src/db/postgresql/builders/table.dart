import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

import 'package:aqueduct/src/db/postgresql/builders/column.dart';
import 'package:aqueduct/src/db/postgresql/builders/expression.dart';
import 'package:aqueduct/src/db/postgresql/builders/sort.dart';
import 'package:aqueduct/src/db/postgresql/postgresql_query.dart';
import 'package:aqueduct/src/db/query/matcher_expression.dart';
import 'package:aqueduct/src/db/query/predicate.dart';
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

    if (query.predicate != null) {
      predicates.add(query.predicate);
    }

    query.subQueries?.forEach((relationshipDesc, subQuery) {
      var join = new TableBuilder(subQuery, parent: this, joinedBy: relationshipDesc);

      addJoinTableBuilder(join);
    });

    predicates.addAll(propertyExpressionsFromObject(query.expressions).map((c) => c.predicate));
  }

  TableBuilder.implicit(this.parent, this.joinedBy) :
    entity = joinedBy.inverse.entity {
    returningValues = [];
    columnSortBuilders = [];
  }

  final ManagedEntity entity;
  final TableBuilder parent;
  final ManagedRelationshipDescription joinedBy;
  final PersistentJoinType type = PersistentJoinType.leftOuter;

  final List<QueryPredicate> predicates = [];

  String tableAlias;
  List<ColumnSortBuilder> columnSortBuilders;
  List<Returnable> returningValues;
  Map<String, dynamic> variables;
  int aliasCounter = 0;
  bool hasImplicitJoins = false;
  QueryPredicate _joinCondition;

  bool get isImplicitlyJoined => returningValues.isEmpty;

  bool get isToMany {
    return joinedBy.relationshipType == ManagedRelationshipType.hasMany;
  }

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

  String get tableReference {
    return tableAlias ?? entity.tableName;
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

  /// Translates QueryExpressions to ExpressionMappers.
  ///
  /// This function gets called 'recursively' in the sense that each table being selected
  /// invokes this method. If a predicate references a property in a related table,
  /// a join occurs. If the query does not currently join that table, an implicit row
  /// mapper is created and passed to subsequent invocations. This triggers a join
  /// but also allows other joins to disambiguate column names by prefixing the parameter
  /// name.
  ///
  ///
  List<ColumnExpressionBuilder> propertyExpressionsFromObject(List<QueryExpression<dynamic, dynamic>> expressions,
      {bool disambiguateVariableNames: false}) {
    if (expressions == null) {
      return [];
    }

    var prefix = disambiguateVariableNames ? "implicit_" : "";

    return expressions
        .map((expression) {
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
              return [
                new ColumnExpressionBuilder(this, lastElement, expression.expression, additionalVariablePrefix: prefix)
              ];
            }
          } else if (isForeignKey) {
            return [
              new ColumnExpressionBuilder(this, expression.keyPath.path.first, expression.expression,
                  additionalVariablePrefix: prefix)
            ];
          }

          // If we fall thru to here, then we're either referencing a has-a relationship property
          // directly or we have a key-path that we need to further traverse.
          // We'll either create an implicit join on the table, or if we're already joining on that table,
          // we'll make sure to use that joined table.

          bool disambiguate = true;

          // Let's see if we already have a join for this relationship
          // and if not, create an implicit one.
          TableBuilder joinedTable = returningValues
              .where((m) => m is TableBuilder)
              .firstWhere((m) => (m as TableBuilder).isJoinOnProperty(firstElement), orElse: () => null);

          if (joinedTable == null) {
            disambiguate = false;

            joinedTable = new TableBuilder.implicit(this, firstElement);
            addJoinTableBuilder(joinedTable);
          }

          // Then build the expression relative to the joined table
          // If we have accessed a property of this property, we'll duplicate the expression object and lop off the key path
          // so that it can be resolved relative to the joined table. Otherwise, do the same but add a primary key instead of remove it.
          if (isPropertyOnThisEntity) {
            final inversePrimaryKey =
                (lastElement as ManagedRelationshipDescription).inverse.entity.primaryKeyAttribute;
            final expr = new QueryExpression(new KeyPath(inversePrimaryKey))..expression = expression.expression;
            return joinedTable.propertyExpressionsFromObject([expr], disambiguateVariableNames: disambiguate);
          }

          return joinedTable.propertyExpressionsFromObject([new QueryExpression.forNestedProperty(expression, 1)],
              disambiguateVariableNames: disambiguate);
        })
        .expand((expressions) => expressions)
        .toList();
  }

  void addJoinTableBuilder(TableBuilder r) {
    returningValues.add(r);

    if (!r.isImplicitlyJoined) {
      // If we're joining a table with the intent of returning its columns,
      // then we need to remove make sure we aren't also fetching its foreign key
      // in the parent table
      returningValues.removeWhere((m) {
        if (m is ColumnBuilder) {
          return identical(m.property, r.joinedBy);
        }

        return false;
      });
      columnSortBuilders.addAll(r.columnSortBuilders);
    } else {
      hasImplicitJoins = true;
      validateImplicitJoin(r);
      predicates.addAll(r.predicates);
    }
  }

  void validateImplicitJoin(TableBuilder table) {
    // Check implicit row mappers for cycles
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

  ManagedRelationshipDescription get foreignKeyProperty =>
      joinedBy.relationshipType == ManagedRelationshipType.belongsTo ? joinedBy : joinedBy.inverse;

  QueryPredicate get joinCondition {
    if (parent == null) {
      return null;
    }

    if (_joinCondition == null) {
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
      _joinCondition = new QueryPredicate("$leftColumn=$rightColumn", null);

      if (predicates.isNotEmpty) {
        final all = new List<QueryPredicate>.from(predicates);
        all.add(_joinCondition);
        _joinCondition = QueryPredicate.andPredicates(all);
      }
    }

    return _joinCondition;
  }

  String get innerSelectString {
    var nestedJoins =
    returningValues.where((m) => m is TableBuilder).map((rm) => (rm as TableBuilder).joinString).join(" ");

    var flattenedColumns = returningColumns;
    var columnsWithNamespace = flattenedColumns.map((p) => p.columnName(withTableNamespace: true)).join(",");
    var columnsWithoutNamespace = flattenedColumns.map((p) => p.columnName()).join(",");

    var outerWhere = QueryPredicate.andPredicates(predicates);
    var outerWhereString = "";
    if (outerWhere != null) {
      outerWhereString = " WHERE ${outerWhere.format}";
    }

    var selectString = "SELECT $columnsWithNamespace FROM $tableNameString $nestedJoins";
    var alias = "$tableReference($columnsWithoutNamespace)";
    return "LEFT OUTER JOIN ($selectString$outerWhereString) $alias ON ${joinCondition.format}";
  }

  String get joinString {
    if (hasImplicitJoins) {
      return innerSelectString;
    }

    var thisJoin = "LEFT OUTER JOIN $tableNameString ON ${joinCondition.format}";

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
