part of aqueduct;

/// An representation of a database operation.
///
/// Queries are used to find, update, insert, delete and count objects in a database.

class Query<ModelType extends Model> {
  Query() {

  }

  Query.withModelType(this._modelType) {

  }

  Type _modelType;
  Type get modelType => _modelType ?? ModelType;

  Map<String, Query> subQueries;

  /// Number of seconds before a Query times out.
  ///
  /// A Query will fail and throw a [QueryException] if [timeoutInSeconds] seconds elapse before the query completes.
  int timeoutInSeconds = 30;

  /// Limits the number of objects returned from the Query.
  ///
  /// Defaults to 0. When zero, there is no limit to the number of objects returned from the Query.
  int fetchLimit = 0;

  /// Offsets the rows returned.
  ///
  /// The set of rows returned will exclude the first [offset] number of rows selected in the query.
  int offset = 0;

  /// A specifier for a page of results.
  ///
  /// Defaults to null. Use a [QueryPage] along with [fetchLimit] when wanting to return a large set of data
  /// across multiple queries.
  QueryPage pageDescriptor;

  /// A list of sorting descriptors for the result set.
  ///
  /// By default, results are not sorted. Sort descriptors are evaluated in order, thus the first sort descriptor
  /// is applies first, the second to break ties, and so on.
  List<SortDescriptor> sortDescriptors;

  /// A predicate for filtering the result or operation set.
  ///
  /// A predicate will identify the rows being accessed, see [Predicate] for more details.
  Predicate predicate;

  /// Values to be used when inserting or updating an object.
  ///
  /// Keys must be the name of the property on the model object. Prefer to use [valueObject] instead.
  Map<String, dynamic> values;

  /// Values to be used when inserting or updating an object.
  ///
  /// Will generate the [values] for this [Query] using values from this object. For example, the following
  /// code would generate the values map {'name' = 'Joe', 'id' = 2}:
  ///     var user = new User()
  ///       ..name = 'Joe'
  ///       ..id = 2;
  ///     var q = new Query<User>()
  ///       ..valueObject = user;
  ///
  ModelType valueObject;

  /// A list of properties to be returned by the Query.
  ///
  /// By default, [resultKeys] is null and therefore all objects returned will contain all properties
  /// of the object. (Unless those properties are marked as hasOne or hasMany relationships.) Specifying
  /// an explicit list of keys will return only those properties. Keys must match the names of the properties
  /// in of [modelType].
  List<String> resultKeys;

  /// Inserts the data represented by this Query into the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// The [Query] must have its [valueObject] or [values] property set. This action method will
  /// insert a row with the data supplied in those fields to the database represented by [adapter]. The return value is
  /// a [Future] with the inserted object. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.valueObject = new User();
  ///       var newUser = await q.insert(adapter);
  ///
  Future<ModelType> insert({ModelContext context: null}) async {
    return await (context ?? ModelContext.defaultContext).executeInsertQuery(this);
  }

  /// Updates rows in the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// Update queries update the values of the rows identified by [predicate] or [predicateObject]
  /// with the values in [valueObject] or [values] in the database represented by [adapter]. Example:
  ///
  ///       var existingUser = ...;
  ///       existingUser.name = "Bob";
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : existingUser.id});
  ///       q.valueObject = existingUser;
  ///       var updatedUsers = await q.update(adapter);
  Future<List<ModelType>> update({ModelContext context: null}) async {
    return await (context ?? ModelContext.defaultContext).executeUpdateQuery(this);
  }

  /// Fetches rows in the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// Fetch queries will return objects for the rows identified by [predicate] or [predicateObject] from
  /// the database represented by [adapter]. Example:
  ///
  ///       var q = new Query<User>();
  ///       var allUsers = q.fetch(adapter);
  ///
  Future<List<ModelType>> fetch({ModelContext context: null}) async {
    return await (context ?? ModelContext.defaultContext).executeFetchQuery(this);
  }

  /// Fetches a single object from the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// This method will return a single object identified by [predicate] or [predicateObject] from
  /// the database represented by [adapter]. If no match is found, this method returns [null].
  /// If more than one match is found, this method throws an exception. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var user = await q.fetchOne(adapter);
  Future<ModelType> fetchOne({ModelContext context: null}) async {
    var results = await (context ?? ModelContext.defaultContext).executeFetchQuery(this);
    if (results.length == 1) {
      return results.first;
    }
    return null;
  }

  /// Deletes rows from the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// This method will delete rows identified by [predicate] or [predicateObject]
  /// from the database represented by [adapter] and returns the number of rows affected.
  /// Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var deleted = await q.delete(adapter);
  ///
  Future<int> delete({ModelContext context: null}) async {
    return await (context ?? ModelContext.defaultContext).executeDeleteQuery(this); // or null
  }

  /// Returns the number of rows matching this [Query] in the database represented by [context] (defaults to [ModelContext.defaultContext]).
  ///
  /// This method will return the number of rows identified by [predicate] or [predicateObject]
  /// from the database represented by [adapter]. Example:
  ///
  /// var q = new Query<User>();
  /// var count = await q.count(adapter);
  ///
  Future<int> count({ModelContext context: null}) async {
    return await (context ?? ModelContext.defaultContext).executeCountQuery(this); // or null
  }
}

/// An exception describing an issue with a query.
///
/// A suggested HTTP status code based on the type of exception will always be available.
class QueryException extends HttpResponseException {

  /// An error code defined by the implementing adapter.
  final int errorCode;

  /// An optional stack trace at the site of the throw.
  final StackTrace stackTrace;

  QueryException(int statusCode, String message, this.errorCode,
      {StackTrace stackTrace: null})
      : super(statusCode, message), this.stackTrace = stackTrace;

  String toString() {
    return "QueryException: ${message} ${errorCode} ${statusCode} ${stackTrace}";
  }
}
