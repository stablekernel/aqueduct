part of aqueduct;

/// The operation a Query can perform.
enum QueryType {
  /// Specifies that the Query will retrieve objects.
  fetch,

  /// Specifies that the Query will update existing object.
  update,

  /// Specifies that the Query will insert new objects.
  insert,

  /// Specifies that the Query will delete existing objects.
  delete,

  /// Specifies that the Query will only return the number of objects that it finds.
  count,

  /// Specifies that the Query is a subquery as part of a larger query
  join
}

/// An representation of a database operation.
///
/// Queries are used to find, update, insert, delete and count objects in a database.

class Query<ModelType extends Model> {
  Query() {
    entity = ModelEntity.entityForType(ModelType);
  }

  Query.withModelType(this._modelType) {
    entity = ModelEntity.entityForType(this._modelType);
  }

  Type _modelType;
  Type get modelType =>_modelType ?? ModelType;

  /// Type of model object this Query deals with.
  ///
  /// This property is defined by the generic ModelType.
  ModelEntity entity;

  /// The action this query performs.
  ///
  /// This property is set during execution of the action methods such as [insert], [fetch], [fetchOne], etc.
  /// This method is used by adapter implementations to determine the type of action to execute. Client code
  /// should not use it, as the [Query] is effectively done once the action method is applied.
  QueryType get queryType => _queryType;
  QueryType _queryType;

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

  ///
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

  /// Inserts the data represented by this Query into the database represented by [adapter].
  ///
  /// The [Query] must have its [valueObject] or [values] property set. This action method will
  /// insert a row with the data supplied in those fields to the database represented by [adapter]. The return value is
  /// a [Future] with the inserted object. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.valueObject = new User();
  ///       var newUser = await q.insert(adapter);
  ///
  Future<ModelType> insert(QueryAdapter adapter) async {
    this._queryType = QueryType.insert;

    var results = await _execute(adapter);
    if (results.length == 1) {
      return results.first;
    }
    throw new QueryException(500, "Query insert for ${ModelType} did not yield results", -1);
  }

  /// Inserts the [object] into the database represented by [adapter].
  ///
  /// This is a convenience for setting [valueObject] or [values]. This action method will
  /// insert a row with the [object] to the database represented by [adapter]. The return value is
  /// a [Future] with the inserted object. Example:
  ///
  ///       var q = new Query<User>();
  ///       var newUser = await q.insertObject(adapter, new User());
  ///
  Future<ModelType> insertObject(QueryAdapter adapter, ModelType object) async {
    this._queryType = QueryType.insert;
    this.valueObject = object;
    return insert(adapter);
  }

  /// Updates rows in the database represented by [adapter].
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
  Future<List<ModelType>> update(QueryAdapter adapter) async {
    this._queryType = QueryType.update;

    return await _execute(adapter);
  }

  /// Fetches rows in the database represented by [adapter].
  ///
  /// Fetch queries will return objects for the rows identified by [predicate] or [predicateObject] from
  /// the database represented by [adapter]. Example:
  ///
  ///       var q = new Query<User>();
  ///       var allUsers = q.fetch(adapter);
  ///
  Future<List<ModelType>> fetch(QueryAdapter adapter) async {
    this._queryType = QueryType.fetch;
    return await _execute(adapter);
  }

  /// Fetches a single object from the database represented by [adapter].
  ///
  /// This method will return a single object identified by [predicate] or [predicateObject] from
  /// the database represented by [adapter]. If no match is found, this method returns [null].
  /// If more than one match is found, this method throws an exception. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var user = await q.fetchOne(adapter);
  Future<ModelType> fetchOne(QueryAdapter adapter) async {
    this._queryType = QueryType.fetch;

    var results = await _execute(adapter);

    if (results.length > 1) {
      throw new QueryException(500, "Tried to fetch single instance of ${ModelType}, but found many.", -1);
    }

    if (results.length == 1) {
      return results.first;
    }

    return null;
  }

  /// Deletes rows from the database represented by [adapter].
  ///
  /// This method will delete rows identified by [predicate] or [predicateObject]
  /// from the database represented by [adapter] and returns the number of rows affected.
  /// Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var deleted = await q.delete(adapter);
  ///
  Future<int> delete(QueryAdapter adapter) async {
    this._queryType = QueryType.delete;

    return await _execute(adapter);
  }

  /// Returns the number of rows matching this [Query] in the database represented by [adapter].
  ///
  /// This method will return the number of rows identified by [predicate] or [predicateObject]
  /// from the database represented by [adapter]. Example:
  ///
  /// var q = new Query<User>();
  /// var count = await q.count(adapter);
  ///
  Future<int> count(QueryAdapter adapter) async {
    this._queryType = QueryType.count;

    return await _execute(adapter);
  }

  /// Executes a fully formed query and returns a list of results.
  ///
  /// A [Query] must have a [modelType] and [type] to be executed. This will schedule execution
  /// and the results will be returned in a List. Not all Queries will return objects (like delete or count).
  Future<dynamic> _execute(QueryAdapter adapter) {
    return adapter
        .execute(this)
        .timeout(new Duration(seconds: timeoutInSeconds), onTimeout: () {
      throw new QueryException(503, "Query Timeout", -1);
    });
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
