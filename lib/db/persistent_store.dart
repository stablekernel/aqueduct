part of aqueduct;

/// An interface for implementing persistent storage.
///
/// Implementors of this class serve as the bridge between [Query]s and a specific database.
abstract class PersistentStore {
  /// Executes an arbitrary command.
  Future execute(String sql);

  /// Closes the underlying database connection.
  Future close();

  Future<List<MappingElement>> executeInsertQuery(PersistentStoreQuery q);

  /// Return a list of rows, where each row is a list of MappingElements that correspond to columns.
  ///
  /// The [PersistentStoreQuery] will contain an ordered list of columns to include in the result.
  /// The return value from this method MUST match that same order.
  Future<List<List<MappingElement>>> executeFetchQuery(PersistentStoreQuery q);
  Future<int> executeDeleteQuery(PersistentStoreQuery q);
  Future<List<List<MappingElement>>> executeUpdateQuery(PersistentStoreQuery q);

  Predicate comparisonPredicate(PropertyDescription desc, MatcherOperator operator, dynamic value);
  Predicate containsPredicate(PropertyDescription desc, Iterable<dynamic> values);
  Predicate nullPredicate(PropertyDescription desc, bool isNull);
  Predicate rangePredicate(PropertyDescription desc, dynamic lhsValue, dynamic rhsValue, bool insideRange);
  Predicate stringPredicate(PropertyDescription desc, StringMatcherOperator operator, dynamic value);

  List<String> createTable(SchemaTable table, {bool isTemporary: false});
}