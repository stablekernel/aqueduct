import '../managed/managed.dart';

import 'schema_table.dart';

export 'migration.dart';
export 'schema_builder.dart';
export 'schema_column.dart';
export 'schema_table.dart';

/// Thrown when a [Schema] encounters an error.
class SchemaException implements Exception {
  SchemaException(this.message);

  String message;

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
  bool matches(Schema schema, [List<String> reasons]) {
    var matches = true;

    for (var receiverTable in tables) {
      var matchingArgTable = schema[receiverTable.name];
      if (matchingArgTable == null) {
        matches = false;
        reasons?.add(
            "Compared schema does not contain '${receiverTable.name}', but that table exists in receiver schema.");
      } else {
        if (!receiverTable.matches(matchingArgTable, reasons)) {
          matches = false;
        }
      }
    }

    if (schema.tables.length > tables.length) {
      matches = false;
      schema.tables.where((st) => this[st.name] == null).forEach((st) {
        reasons?.add(
            "Receiver schema does not contain '${st.name}', but that table exists in compared schema.");
      });
    }

    return matches;
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
