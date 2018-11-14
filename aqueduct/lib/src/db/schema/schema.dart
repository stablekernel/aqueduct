import '../managed/managed.dart';

import 'schema_table.dart';

export 'migration.dart';
export 'schema_builder.dart';
export 'schema_column.dart';
export 'schema_table.dart';

/// A portable representation of a database schema.
///
/// Instances of this type contain the database-only details of a [ManagedDataModel] and are typically
/// instantiated from [ManagedDataModel]s. The purpose of this type is to have a portable, differentiable representation
/// of an application's data model for use in external tooling.
class Schema {
  /// Creates an instance of this type with a specific set of [tables].
  ///
  /// Prefer to use [Schema.fromDataModel].
  Schema(List<SchemaTable> tables) : _tableStorage = tables;

  /// Creates an instance of this type from [dataModel].
  ///
  /// This is preferred method of creating an instance of this type. Each [ManagedEntity]
  /// in [dataModel] will correspond to a [SchemaTable] in [tables].
  Schema.fromDataModel(ManagedDataModel dataModel) {
    _tables = dataModel.entities.map((e) => SchemaTable.fromEntity(e)).toList();
  }

  /// Creates a deep copy of [otherSchema].
  Schema.from(Schema otherSchema) {
    _tables = otherSchema?.tables
            ?.map((table) => SchemaTable.from(table))
            ?.toList() ??
        [];
  }

  /// Creates a instance of this type from [map].
  ///
  /// [map] is typically created from [asMap].
  Schema.fromMap(Map<String, dynamic> map) {
    _tables = (map["tables"] as List<Map<String, dynamic>>)
        .map((t) => SchemaTable.fromMap(t))
        .toList();
  }

  /// Creates an empty schema.
  Schema.empty() {
    _tables = [];
  }

  /// The tables in this database.
  ///
  /// Returns an immutable list of tables in this schema.
  List<SchemaTable> get tables => List.unmodifiable(_tableStorage ?? []);

  // Do not set this directly. Use _tables= instead.
  List<SchemaTable> _tableStorage;

  // ignore: avoid_setters_without_getters
  set _tables(List<SchemaTable> tables) {
    _tableStorage = tables ?? [];
    _tableStorage.forEach((t) => t.schema = this);
  }

  /// Gets a table from [tables] by that table's name.
  ///
  /// See [tableForName] for details.
  SchemaTable operator [](String tableName) => tableForName(tableName);

  /// The differences between two schemas.
  ///
  /// In the return value, the receiver is the [SchemaDifference.expectedSchema]
  /// and [otherSchema] is [SchemaDifference.actualSchema].
  SchemaDifference differenceFrom(Schema otherSchema) {
    return SchemaDifference(this, otherSchema);
  }

  /// Adds a table to this instance.
  ///
  /// Sets [table]'s [SchemaTable.schema] to this instance.
  void addTable(SchemaTable table) {
    if (this[table.name] != null) {
      throw SchemaException(
          "Table ${table.name} already exists and cannot be added.");
    }

    _tableStorage.add(table);
    table.schema = this;
  }

  void replaceTable(SchemaTable existingTable, SchemaTable newTable) {
    if (!_tableStorage.contains(existingTable)) {
      throw SchemaException(
          "Table ${existingTable.name} does not exist and cannot be replaced.");
    }

    var index = _tableStorage.indexOf(existingTable);
    _tableStorage[index] = newTable;
    newTable.schema = this;
    existingTable.schema = null;
  }

  void renameTable(SchemaTable table, String newName) {
    throw SchemaException("Renaming a table not yet implemented!");
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

  /// Removes a table from this instance.
  ///
  /// [table] must be an instance in [tables] or an exception is thrown.
  /// Sets [table]'s [SchemaTable.schema] to null.
  void removeTable(SchemaTable table) {
    if (!tables.contains(table)) {
      throw SchemaException("Table ${table.name} does not exist in schema.");
    }
    table.schema = null;
    _tableStorage.remove(table);
  }

  /// Returns a [SchemaTable] for [name].
  ///
  /// [name] is case-insensitively compared to every [SchemaTable.name]
  /// in [tables]. If no table with this name exists, null is returned.
  ///
  /// Note: tables are typically prefixed with an underscore when using
  /// Aqueduct naming conventions for [ManagedObject].
  SchemaTable tableForName(String name) {
    var lowercaseName = name.toLowerCase();

    return tables.firstWhere((t) => t.name.toLowerCase() == lowercaseName,
        orElse: () => null);
  }

  /// Emits this instance as a transportable [Map].
  Map<String, dynamic> asMap() {
    return {"tables": tables.map((t) => t.asMap()).toList()};
  }
}

/// The difference between two compared [Schema]s.
///
/// This class is used for comparing schemas for validation and migration.
class SchemaDifference {
  /// Creates a new instance that represents the difference between [expectedSchema] and [actualSchema].
  ///
  SchemaDifference(this.expectedSchema, this.actualSchema) {
    for (var expectedTable in expectedSchema.tables) {
      var actualTable = actualSchema[expectedTable.name];
      if (actualTable == null) {
        _differingTables.add(SchemaTableDifference(expectedTable, null));
      } else {
        var diff = expectedTable.differenceFrom(actualTable);
        if (diff.hasDifferences) {
          _differingTables.add(diff);
        }
      }
    }

    _differingTables.addAll(actualSchema.tables
        .where((t) => expectedSchema[t.name] == null)
        .map((unexpectedTable) {
      return SchemaTableDifference(null, unexpectedTable);
    }));
  }

  /// The 'expected' schema.
  final Schema expectedSchema;

  /// The 'actual' schema.
  final Schema actualSchema;

  /// Whether or not [expectedSchema] and [actualSchema] have differences.
  ///
  /// If false, both [expectedSchema] and [actualSchema], their tables, and those tables' columns are identical.
  bool get hasDifferences => _differingTables.isNotEmpty;

  /// Human-readable messages to describe differences between [expectedSchema] and [actualSchema].
  ///
  /// Empty is [hasDifferences] is false.
  List<String> get errorMessages =>
      _differingTables.expand((diff) => diff.errorMessages).toList();

  /// The differences, if any, between tables in [expectedSchema] and [actualSchema].
  List<SchemaTableDifference> get tableDifferences => _differingTables;

  List<SchemaTable> get tablesToAdd {
    return _differingTables
        .where((diff) => diff.expectedTable == null && diff.actualTable != null)
        .map((d) => d.actualTable)
        .toList();
  }

  List<SchemaTable> get tablesToDelete {
    return _differingTables
        .where((diff) => diff.expectedTable != null && diff.actualTable == null)
        .map((diff) => diff.expectedTable)
        .toList();
  }

  List<SchemaTableDifference> get tablesToModify {
    return _differingTables
        .where((diff) => diff.expectedTable != null && diff.actualTable != null)
        .toList();
  }

  List<SchemaTableDifference> _differingTables = [];
}

/// Thrown when a [Schema] encounters an error.
class SchemaException implements Exception {
  SchemaException(this.message);

  String message;

  @override
  String toString() => "Invalid schema. $message";
}
