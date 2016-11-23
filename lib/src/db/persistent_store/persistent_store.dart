import 'dart:async';
import '../query/query.dart';
import '../schema/schema.dart';
import 'persistent_store_query.dart';
import '../managed/managed.dart';
export 'persistent_store_query.dart';

/// An interface for implementing persistent storage.
///
/// You rarely need to use this class directly. See [Query] for how to interact with instances of this class.
/// Implementors of this class serve as the bridge between [Query]s and a specific database.
abstract class PersistentStore {
  /// Executes an arbitrary command.
  Future execute(String sql, {Map<String, dynamic> substitutionValues});

  /// Closes the underlying database connection.
  Future close();

  /// Inserts a row described by [q] into the database and returns a [List] of its column values.
  ///
  /// Each [PersistentColumnMapping] is a column-value pair from the database.
  Future<List<PersistentColumnMapping>> executeInsertQuery(
      PersistentStoreQuery q);

  /// Return a list of rows, where each row is a [List] of [PersistentColumnMapping]s.
  ///
  /// Each [PersistentColumnMapping] is a column-value pair from the database.
  /// The [PersistentStoreQuery] will contain an ordered list of columns to include in the result.
  /// The return value from this method MUST match that same order.
  Future<List<List<PersistentColumnMapping>>> executeFetchQuery(
      PersistentStoreQuery q);

  /// Deletes rows described by [q].
  ///
  /// Returns the number of rows deleted.
  Future<int> executeDeleteQuery(PersistentStoreQuery q);

  /// Updates rows described by [q] and returns a [List] of rows that were altered.
  ///
  /// Each [PersistentColumnMapping] is a column-value pair from the database.
  Future<List<List<PersistentColumnMapping>>> executeUpdateQuery(
      PersistentStoreQuery q);

  QueryPredicate comparisonPredicate(
      ManagedPropertyDescription desc, MatcherOperator operator, dynamic value);
  QueryPredicate containsPredicate(
      ManagedPropertyDescription desc, Iterable<dynamic> values);
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull);
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
      dynamic lhsValue, dynamic rhsValue, bool insideRange);
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
      StringMatcherOperator operator, dynamic value);

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
