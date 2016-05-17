part of aqueduct;

/// An interface for querying databases.
///
/// This interface must be implemented by a database provider by implementing
/// run and execute. An adapter is responsible for providing a connection to a database.
abstract class QueryAdapter {
  /// Runs an arbitrary command.
  ///
  /// To allow clients to perform commands that just can't be accomplished through normal usage.
  /// Adapters should implement this method to run [format] after interpolating [values]
  /// into the string. The return value is intentionally nebulous and defined by the adapter.
  Future run(String format, {Map<String, dynamic> values});

  /// Executes a Query on the database this adapter is connected to.
  ///
  /// The primary action mechanism, this method will execute this Query
  /// and return the appropriate values for the type of query.
  ///
  /// Fetch queries return a list of model objects, as defined by the Query generic type.
  /// Update queries return a list of model objects, as defined by the Query generic type.
  /// Insert queries return a single model object, as defined by the Query generic type.
  /// Delete queries return a count of affected rows.
  /// Count queries return a count of selected rows.
  Future<dynamic> execute(Query req);


  /// Closes the underlying database connection.
  void close() {}
}
