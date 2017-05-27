import 'dart:mirrors';

import '../managed/managed.dart';

import 'schema_table.dart';
import 'schema_column.dart';

export 'migration.dart';
export 'schema_builder.dart';
export 'schema_column.dart';
export 'schema_table.dart';
export 'migration_builder.dart';

/// Thrown when a [Schema] encounters an error.
class SchemaException implements Exception {
  SchemaException(this.message);

  String message;

  @override
  String toString() => "SchemaException: $message";
}

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
  operator [](String tableName) => tableForName(tableName);

  /// Whether or not two schemas match.
  ///
  /// If passing [reasons], the reasons for a mismatch are added to the passed in [List].
  SchemaDifference differenceFrom(Schema schema) {
    var actualSchema = schema;

    var differences = new SchemaDifference()
      ..expectedSchema = this
      ..actualSchema = actualSchema;

    for (var expectedTable in tables) {
      var actualTable = actualSchema[expectedTable.name];
      if (actualTable == null) {
        differences.differingTables.add(new SchemaTableDifference()
          ..actualTable = null
          ..expectedTable = expectedTable);
      } else {
        var diff = expectedTable.differenceFrom(actualTable);
        if (diff.hasDifferences) {
          differences.differingTables.add(diff);
        }
      }
    }

    differences.differingTables.addAll(actualSchema.tables
        .where((t) => this[t.name] == null)
        .map((unexpectedTable) {
      return new SchemaTableDifference()
        ..actualTable = unexpectedTable
        ..expectedTable = null;
    }));

    return differences;
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

  List<SchemaTable> _orderedTables(
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
  bool get hasDifferences => differingTables.length > 0;
  List<String> get errorMessages =>
      differingTables.expand((diff) => diff.errorMessages).toList();

  Schema expectedSchema;
  Schema actualSchema;

  List<SchemaTableDifference> differingTables = [];

  List<String> get tableNamesToAdd =>
      differingTables
          .where((diff) => diff.expectedTable == null && diff.actualTable != null)
          .map((diff) => diff.actualTable.name)
          .toList();

  List<String> get tableNamesToDelete =>
      differingTables
          .where((diff) => diff.expectedTable != null && diff.actualTable == null)
          .map((diff) => diff.expectedTable.name)
          .toList();
}

class SchemaTableDifference {
  bool get hasDifferences =>
      differingColumns.length > 0 ||
      expectedTable?.name?.toLowerCase() != actualTable?.name?.toLowerCase() ||
      (expectedTable == null && actualTable != null) ||
      (actualTable == null && expectedTable != null);

  List<String> get errorMessages {
    if (expectedTable == null && actualTable != null) {
      return [
        "Table '${actualTable}' should NOT exist, but is created by migration files."
      ];
    } else if (expectedTable != null && actualTable == null) {
      return [
        "Table '${expectedTable}' should exist, but it is NOT created by migration files."
      ];
    }

    return differingColumns.expand((diff) => diff.errorMessages(this)).toList();
  }

  SchemaTable expectedTable;
  SchemaTable actualTable;

  List<SchemaColumnDifference> differingColumns = [];

  List<String> get columnNamesToAdd =>
      differingColumns
          .where((diff) => diff.expectedColumn == null && diff.actualColumn != null)
          .map((diff) => diff.actualColumn.name)
          .toList();

  List<String> get columnNamesToDelete =>
      differingColumns
          .where((diff) => diff.expectedColumn != null && diff.actualColumn == null)
          .map((diff) => diff.expectedColumn.name)
          .toList();
}

class SchemaColumnDifference {
  bool get hasDifferences =>
      differingProperties.length > 0 ||
      (expectedColumn == null && actualColumn != null) ||
      (actualColumn == null && expectedColumn != null);

  List<String> errorMessages(SchemaTableDifference tableDiff) {
    if (expectedColumn == null && actualColumn != null) {
      return [
        "Column '${actualColumn.name}' in table '${tableDiff.actualTable.name}' should NOT exist, but is created by migration files"
      ];
    } else if (expectedColumn != null && actualColumn == null) {
      return [
        "Column '${expectedColumn.name}' in table '${tableDiff.actualTable.name}' should exist, but is NOT created by migration files"
      ];
    }

    return differingProperties.map((propertyName) {
      var expectedValue =
          reflect(expectedColumn).getField(new Symbol(propertyName)).reflectee;
      var actualValue =
          reflect(actualColumn).getField(new Symbol(propertyName)).reflectee;

      return "Column '${expectedColumn.name}' in table '${tableDiff.actualTable.name}' expected "
          "'$expectedValue' for '$propertyName', but migration files yield '$actualValue'";
    }).toList();
  }

  SchemaColumn expectedColumn;
  SchemaColumn actualColumn;

  List<String> differingProperties = [];
}
