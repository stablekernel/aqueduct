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
  Schema(List<SchemaTable> tables) : _tableStorage = tables;

  Schema.fromDataModel(ManagedDataModel dataModel) {
    _tables =
        dataModel.entities.map((e) => new SchemaTable.fromEntity(e)).toList();
  }

  Schema.from(Schema otherSchema) {
    _tables = otherSchema?.tables
        ?.map((table) => new SchemaTable.from(table))
        ?.toList() ??
        [];
  }

  Schema.fromMap(Map<String, dynamic> map) {
    _tables = (map["tables"] as List<Map<String, dynamic>>)
        .map((t) => new SchemaTable.fromMap(t))
        .toList();
  }

  Schema.empty() {
    _tables = [];
  }

  /// The tables in this database.
  ///
  /// Returns an immutable list of tables in this schema.
  List<SchemaTable> get tables => new List.unmodifiable(_tableStorage);

  /// A list of tables in this database that are ordered by dependencies.
  ///
  /// This ordering ensures that tables that depend on another table (like those that have a foreign key reference) come
  /// after the tables they depend on.
  List<SchemaTable> get dependencyOrderedTables => _orderedTables([], tables);

  // Do not set this directly. Use _tables= instead.
  List<SchemaTable> _tableStorage;

  set _tables(List<SchemaTable> tables) {
    _tableStorage = tables ?? [];
    _tableStorage.forEach((t) => t.schema = this);
  }

  /// Gets a table from [tables] by that table's name.
  SchemaTable operator [](String tableName) => tableForName(tableName);

  /// The differences between two schemas.
  ///
  /// In the return value, the receiver is the [SchemaDifference.expectedSchema]
  /// and [otherSchema] is [SchemaDifference.actualSchema].
  SchemaDifference differenceFrom(Schema otherSchema) {
    return new SchemaDifference(this, otherSchema);
  }

  void addTable(SchemaTable table) {
    if (this[table.name] != null) {
      throw new SchemaException("Table ${table.name} already exists.");
    }

    _tableStorage.add(table);
    table.schema = this;
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
    var toRemove = tables.firstWhere(
            (t) => t.name.toLowerCase() == table.name.toLowerCase(),
        orElse: () =>
        throw new SchemaException(
            "Table ${table.name} does not exist in schema."));

    toRemove.schema = null;
    _tableStorage.remove(toRemove);
  }

  SchemaTable tableForName(String name) {
    var lowercaseName = name.toLowerCase();

    return tables.firstWhere((t) => t.name.toLowerCase() == lowercaseName,
        orElse: () => null);
  }

  Map<String, dynamic> asMap() {
    return {"tables": tables.map((t) => t.asMap()).toList()};
  }

  static List<SchemaTable> _orderedTables(List<SchemaTable> tablesAccountedFor,
      List<SchemaTable> remainingTables) {
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

  final Schema expectedSchema;
  final Schema actualSchema;
  List<SchemaTableDifference> differingTables = [];

  bool get hasDifferences => differingTables.length > 0;

  List<String> get errorMessages =>
      differingTables.expand((diff) => diff.errorMessages).toList();

  /// Returns Dart code to change [expectedSchema] to [actualSchema].
  String generateUpgradeSource({List<String> changeList}) {
    var builder = new StringBuffer();

    var tablesToAdd = differingTables
        .where((diff) => diff.expectedTable == null && diff.actualTable != null)
        .map((d) => d.actualTable)
        .toList();
    actualSchema.dependencyOrderedTables
        .where((t) => tablesToAdd.map((toAdd) => toAdd.name).contains(t.name))
        .forEach((t) {
      changeList?.add("Adding table '${t.name}'");
      builder.writeln(createTableSource(t));
    });

    var tablesToRemove = differingTables
        .where((diff) => diff.expectedTable != null && diff.actualTable == null)
        .map((diff) => diff.expectedTable)
        .toList();
    expectedSchema.dependencyOrderedTables.reversed
        .where((t) => tablesToRemove.map((toRemove) => toRemove.name).contains(t.name))
        .forEach((t) {
      changeList?.add("Deleting table '${t.name}'");
      builder.writeln(deleteTableSource(t));
    });

    differingTables
        .where((diff) => diff.expectedTable != null && diff.actualTable != null)
        .forEach((tableDiff) {
      var lines = tableDiff.generateUpgradeSource(changeList: changeList);
      builder.writeln(lines);
    });

    return builder.toString();
  }
  
  static String createTableSource(SchemaTable table) {
    var builder = new StringBuffer();
    builder.writeln(
        'database.createTable(new SchemaTable("${table.name}", [');
    table.columns.forEach((col) {
      builder.writeln("${col.source},");
    });
    builder.writeln("],");

    if (table.uniqueColumnSet != null) {
      var set = table.uniqueColumnSet.map((p) => '"$p"').join(",");
      builder.writeln("uniqueColumnSetNames: [$set],");
    }

    builder.writeln('));');

    return builder.toString();
  }

  static String deleteTableSource(SchemaTable table) {
    return 'database.deleteTable("${table.name}");';
  }
}

/// Thrown when a [Schema] encounters an error.
class SchemaException implements Exception {
  SchemaException(this.message);

  String message;

  @override
  String toString() => "SchemaException: $message";
}