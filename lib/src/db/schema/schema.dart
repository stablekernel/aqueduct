import '../managed/managed.dart';
import 'migration.dart';

import 'schema_table.dart';

export 'migration.dart';
export 'schema_builder.dart';
export 'schema_column.dart';
export 'schema_table.dart';
export 'migration_builder.dart';

/// Represents a database and its tables.
///
/// This class is used internally and during [Migration].
class Schema {
  Schema(this.tables);

  Schema.fromDataModel(ManagedDataModel dataModel) {
    tables =
        dataModel.entities.map((e) => new SchemaTable.fromEntity(e)).toList();
  }

  Schema.from(Schema otherSchema) {
    tables = otherSchema?.tables
            ?.map((table) => new SchemaTable.from(table))
            ?.toList() ??
        [];
  }

  Schema.fromMap(Map<String, dynamic> map) {
    tables = (map["tables"] as List<Map<String, dynamic>>)
        .map((t) => new SchemaTable.fromMap(t))
        .toList();
  }

  Schema.empty() {
    tables = [];
  }

  /// The tables in this database.
  List<SchemaTable> tables;

  /// A list of tables in this database that are ordered by dependencies.
  ///
  /// This ordering ensures that tables that depend on another table (like those that have a foreign key reference) come
  /// after the tables they depend on.
  List<SchemaTable> get dependencyOrderedTables => _orderedTables([], tables);

  /// Gets a table from [tables] by that table's name.
  SchemaTable operator [](String tableName) => tableForName(tableName);

  /// The differences between two schemas.
  SchemaDifference differenceFrom(Schema schema) {
    return new SchemaDifference(this, schema);
  }

  void addTable(SchemaTable table) {
    if (this[table.name] != null) {
      throw new SchemaException("Table ${table.name} already exists.");
    }

    tables.add(table);
  }

  void renameTable(SchemaTable table, String newName) {
    throw new SchemaException("Renaming a table not yet implemented!");
//
//    if (tableForName(newName) != null) {
//      throw new SchemaException("Table ${newName} already exist.");
//    }
//
//    if (!tables.contains(table)) {
//      throw new SchemaException("Table ${table.name} does not exist in schema.");
//    }
//
//    // Rename indices and constraints
//    table.name = newName;
  }

  void removeTable(SchemaTable table) {
    if (this[table.name] == null) {
      throw new SchemaException(
          "Table ${table.name} does not exist in schema.");
    }

    tables
        .removeWhere((st) => st.name.toLowerCase() == table.name.toLowerCase());
  }

  SchemaTable tableForName(String name) {
    var lowercaseName = name.toLowerCase();
    return tables.firstWhere((t) => t.name.toLowerCase() == lowercaseName,
        orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {"tables": tables.map((t) => t.asMap()).toList()};
  }

  static List<SchemaTable> _orderedTables(
      List<SchemaTable> tablesAccountedFor, List<SchemaTable> remainingTables) {
    if (remainingTables.isEmpty) {
      return tablesAccountedFor;
    }

    var tableIsReady = (SchemaTable t) {
      var foreignKeyColumns =
          t.columns.where((sc) => sc.relatedTableName != null).toList();

      if (foreignKeyColumns.isEmpty) {
        return true;
      }

      return foreignKeyColumns.map((sc) => sc.relatedTableName).every(
          (tableName) =>
              tablesAccountedFor.map((st) => st.name).contains(tableName));
    };

    tablesAccountedFor.addAll(remainingTables.where(tableIsReady));

    return _orderedTables(
        tablesAccountedFor,
        remainingTables
            .where((st) => !tablesAccountedFor.contains(st))
            .toList());
  }
}

class SchemaDifference {
  SchemaDifference(this.expectedSchema, this.actualSchema) {
    for (var expectedTable in expectedSchema.tables) {
      var actualTable = actualSchema[expectedTable.name];
      if (actualTable == null) {
        differingTables.add(new SchemaTableDifference(expectedTable, null));
      } else {
        var diff = expectedTable.differenceFrom(actualTable);
        if (diff.hasDifferences) {
          differingTables.add(diff);
        }
      }
    }

    differingTables.addAll(actualSchema.tables
        .where((t) => expectedSchema[t.name] == null)
        .map((unexpectedTable) {
          return new SchemaTableDifference(null, unexpectedTable);
        }));
  }

  Schema expectedSchema;
  Schema actualSchema;
  List<SchemaTableDifference> differingTables = [];

  bool get hasDifferences => differingTables.length > 0;
  List<String> get errorMessages =>
      differingTables.expand((diff) => diff.errorMessages).toList();

  String generateUpgradeSource({List<String> changeList}) {
    var builder = new StringBuffer();

    var tablesToAdd = differingTables
        .where((diff) => diff.expectedTable == null && diff.actualTable != null)
        .map((d) => d.actualTable)
        .toList();
    Schema
        ._orderedTables([], tablesToAdd)
        .forEach((t) {
          changeList?.add("Adding table '${t.name}'");
          builder.writeln(t.migrationCreateCommand);
        });

    var tablesToRemove = differingTables
        .where((diff) => diff.expectedTable != null && diff.actualTable == null)
        .map((diff) => diff.expectedTable)
        .toList();
    Schema
        ._orderedTables([], tablesToRemove)
        .reversed
        .forEach((t) {
          changeList?.add("Deleting table '${t.name}'");
          builder.writeln(t.migrationDeleteCommand);
        });

    differingTables
        .where((tableDiff) => tableDiff.expectedTable != null && tableDiff.actualTable != null)
        .forEach((tableDiff) {
          var lines = tableDiff.generateUpgradeSource(changeList: changeList);
          builder.writeln(lines);
        });

    return builder.toString();
  }
}

/// Thrown when a [Schema] encounters an error.
class SchemaException implements Exception {
  SchemaException(this.message);

  String message;

  @override
  String toString() => "SchemaException: $message";
}