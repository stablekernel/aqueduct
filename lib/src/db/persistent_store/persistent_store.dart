import 'dart:async';
import '../query/query.dart';
import '../schema/schema.dart';
export 'persistent_store_query.dart';

enum PersistentStoreQueryReturnType { rowCount, rows }

/// An interface for implementing persistent storage.
///
/// You rarely need to use this class directly. See [Query] for how to interact with instances of this class.
/// Implementors of this class serve as the bridge between [Query]s and a specific database.
abstract class PersistentStore {
  /// Executes an arbitrary command.
  Future execute(String sql, {Map<String, dynamic> substitutionValues});

  Future<dynamic> executeQuery(
      String formatString, Map<String, dynamic> values, int timeoutInSeconds,
      {PersistentStoreQueryReturnType returnType});

  /// Closes the underlying database connection.
  Future close();

  // -- Schema Ops --

  List<String> createTable(SchemaTable table, {bool isTemporary: false});
  List<String> renameTable(SchemaTable table, String name);
  List<String> deleteTable(SchemaTable table);

  List<String> addColumn(SchemaTable table, SchemaColumn column);
  List<String> deleteColumn(SchemaTable table, SchemaColumn column);
  List<String> renameColumn(
      SchemaTable table, SchemaColumn column, String name);
  List<String> alterColumnNullability(
      SchemaTable table, SchemaColumn column, String unencodedInitialValue);
  List<String> alterColumnUniqueness(SchemaTable table, SchemaColumn column);
  List<String> alterColumnDefaultValue(SchemaTable table, SchemaColumn column);
  List<String> alterColumnDeleteRule(SchemaTable table, SchemaColumn column);

  List<String> addIndexToColumn(SchemaTable table, SchemaColumn column);
  List<String> renameIndex(
      SchemaTable table, SchemaColumn column, String newIndexName);
  List<String> deleteIndexFromColumn(SchemaTable table, SchemaColumn column);

  Future<int> get schemaVersion;
  Future upgrade(int versionNumber, List<String> commands,
      {bool temporary: false});
}
