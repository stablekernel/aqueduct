part of aqueduct;

/// Contains information for building and executing a database operation.
///
/// Queries are used to fetch, update, insert, delete and count objects in a database. A query's [InstanceType] indicates
/// the type of [ManagedObject] subclass' that this query will return as well. The [InstanceType]'s corresponding [ManagedEntity] determines
/// the database table and columns to work with.
class Query<InstanceType extends ManagedObject> {
  /// Creates a new [Query].
  ///
  /// By default, [context] is [ManagedContext.defaultContext]. The [entity] of this instance is found by
  /// evaluating [InstanceType] in [context].
  Query([ManagedContext context]) {
    this.context = context ?? ManagedContext.defaultContext;
    entity = this.context.dataModel.entityForType(InstanceType);
  }

  /// The [ManagedEntity] of the [InstanceType].
  ManagedEntity entity;

  /// The [ManagedContext] this query will be exeuted on.
  ManagedContext context;

  /// A convenience for building [predicate]s in a safe way.
  ///
  /// Use this property instead of providing a [predicate] to filter the rows this query manipulates or fetches. This property
  /// is an instance of [InstanceType] with special [ManagedObject.backingMap] behavior. When you set properties of this property using
  /// matchers (see examples such as [whereEqualTo] and [whereContains]), the underlying database will generate a [QueryPredicate] to
  /// match the behavior of these matches. For example, the following query will generate a predicate that only operates on rows
  /// where 'id' is greater than 1:
  ///
  ///       var q = new Query<Employee>()
  ///           ..matchOn.employeeID = greaterThan(1);
  ///
  /// This property is also used to fetch relationship properties. When [InstanceType] has a has-one or has-many relationship, setting the relationship
  /// property's [ManagedObject.includeInResultSet] will cause this [Query] to also fetch objects of that [ManagedObject]'s type. For example,
  /// the following query will fetch 'Employee's and their 'Task's.
  ///
  ///       var q = new Query<Employee>()
  ///           ..matchOn.tasks.includeInResultSet = true;
  ///
  /// Any relationship property that is included in the result set in this way may have further constraints by setting properties
  /// in its [matchOn].
  ///
  ///       var q = new Query<Employee>()
  ///           ..matchOn.tasks.includeInResultSet = true
  ///           ..matchOn.tasks.matchOn.status = whereEqualTo("Complete");
  InstanceType get matchOn {
    if (_matchOn == null) {
      _matchOn = entity.newInstance() as InstanceType;
      _matchOn._backing = new _ManagedMatcherBacking();
    }
    return _matchOn;
  }

  InstanceType _matchOn;

  /// Confirms that a query has no predicate before executing it.
  ///
  /// This is a safety measure for update and delete queries to prevent accidentally updating or deleting every row.
  /// This flag defaults to false, meaning that if this query is either an update or a delete, but contains no predicate,
  /// it will fail. If a query is meant to update or delete every row on a table, you may set this to true to allow this query to proceed.
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate = false;

  /// Number of seconds before a Query times out.
  ///
  /// A Query will fail and throw a [QueryException] if [timeoutInSeconds] seconds elapse before the query completes.
  int timeoutInSeconds = 30;

  /// Limits the number of objects returned from the Query.
  ///
  /// Defaults to 0. When zero, there is no limit to the number of objects returned from the Query.
  /// This value should be set when using [pageDescriptor] to limit the page size.
  int fetchLimit = 0;

  /// Offsets the rows returned.
  ///
  /// The set of rows returned will exclude the first [offset] number of rows selected in the query. Do not
  /// set this property when using [pageDescriptor].
  int offset = 0;

  /// A specifier for a page of results.
  ///
  /// Defaults to null. Use a [QueryPage] along with [fetchLimit] when fetching a subset of rows from a large data set.
  QueryPage pageDescriptor;

  /// The order in which rows should be returned.
  ///
  /// By default, results are not sorted. Sort descriptors are evaluated in order, thus the first sort descriptor
  /// is applies first, the second to break ties, and so on.
  List<QuerySortDescriptor> sortDescriptors;

  /// A predicate for filtering the result or operation set.
  ///
  /// A predicate will identify the rows being accessed, see [QueryPredicate] for more details. Prefer to use
  /// [matchOn] instead of this property directly.
  QueryPredicate predicate;

  /// Values to be used when inserting or updating an object.
  ///
  /// Keys must be the name of the property on the model object. Prefer to use [values] instead.
  Map<String, dynamic> valueMap;

  /// Values to be used when inserting or updating an object.
  ///
  /// Will generate the [valueMap] for this [Query] using values from this object. This object is created
  /// once accessed, so it is not necessary to create an instance and set this property, but instead,
  /// set properties of this property.
  ///
  /// For example, the following code would generate the values map {'name' = 'Joe', 'job' = 'programmer'}:
  ///     var q = new Query<User>()
  ///       ..values.name = 'Joe
  ///       ..values.job = 'programmer';
  ///
  InstanceType get values {
    if (_valueObject == null) {
      _valueObject = entity.newInstance() as InstanceType;
    }
    return _valueObject;
  }

  void set values(InstanceType obj) {
    _valueObject = obj;
  }

  InstanceType _valueObject;

  /// A list of properties to be fetched by this query.
  ///
  /// Each [InstanceType] will have these properties set when this query is executed. Each property must be
  /// a column-backed property of [InstanceType].
  ///
  /// By default, this property is null, which indicates that the default properties of [InstanceType] should be fetched.
  /// See [ManagedEntity.defaultProperties] for more details.
  List<String> resultProperties;

  /// The properties to be fetched for any nested [ManagedObject]s.
  ///
  /// When executing a query that includes relationship properties (see [matchOn]), this value indicates which properties of those related [ManagedObject]s
  /// are fetched. By default, a related object's default properties are fetched (see [ManagedEntity.defaultProperties]). To specify otherwise,
  /// set the list of desired property names in this [Map]. The key is the [ManagedObject] type of the related object.
  Map<Type, List<String>> nestedResultProperties = {};

  /// Inserts an [InstanceType] into the underlying database.
  ///
  /// The [Query] must have its [values] or [valueMap] property set. This operation will
  /// insert a row with the data supplied in those fields to the database in [context]. The return value is
  /// a [Future] that completes with the newly inserted [InstanceType]. Example:
  ///
  ///       var q = new Query<User>()
  ///         ..values.name = "Joe";
  ///       var newUser = await q.insert();
  Future<InstanceType> insert() async {
    return await context._executeInsertQuery(this);
  }

  /// Updates [InstanceType]s in the underlying database.
  ///
  /// The [Query] must have its [values] or [valueMap] property set and should likely have its [predicate] or [matchOn] set as well. This operation will
  /// update each row that matches the conditions in [predicate]/[matchOn] with the values from [values] or [valueMap]. If no [matchOn] or [predicate] is set,
  /// this method will throw an exception by default, assuming that you don't typically want to update every row in a database table. To specify otherwise,
  /// set [confirmQueryModifiesAllInstancesOnDeleteOrUpdate] to true.
  /// The return value is a [Future] that completes with the any updated [InstanceType]s. Example:
  ///
  ///       var q = new Query<User>()
  ///         ..matchOn.name = "Fred"
  ///         ..values.name = "Joe";
  ///       var usersNamedFredNowNamedJoe = await q.update();
  Future<List<InstanceType>> update() async {
    return await context._executeUpdateQuery(this);
  }

  /// Updates an [InstanceType] in the underlying database.
  ///
  /// This method works the same as [update], except it may only update one row in the underlying database. If this method
  /// ends up modifying multiple rows, an exception is thrown.
  Future<InstanceType> updateOne() async {
    var results = await context._executeUpdateQuery(this);
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new QueryException(QueryExceptionEvent.internalFailure,
        message:
            "updateOne modified more than one row, this is a serious error.");
  }

  /// Fetches [InstanceType]s from the database.
  ///
  /// This operation will return all [InstanceType]s from the database, filtered by [predicate]/[matchOn]. Example:
  ///
  ///       var q = new Query<User>();
  ///       var allUsers = q.fetch();
  ///
  Future<List<InstanceType>> fetch() async {
    return await context._executeFetchQuery(this);
  }

  /// Fetches a single [InstanceType] from the database.
  ///
  /// This method behaves the same as [fetch], but limits the results to a single object.
  Future<InstanceType> fetchOne() async {
    fetchLimit = 1;

    var results = await context._executeFetchQuery(this);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new QueryException(QueryExceptionEvent.requestFailure,
          message:
              "Query expected to fetch one instance, but ${results.length} instances were returned.");
    }
    return null;
  }

  /// Deletes [InstanceType]s from the underlying database.
  ///
  /// This method will delete rows identified by [predicate]/[matchOn]. If no [matchOn] or [predicate] is set,
  /// this method will throw an exception by default, assuming that you don't typically want to delete every row in a database table. To specify otherwise,
  /// set [confirmQueryModifiesAllInstancesOnDeleteOrUpdate] to true.
  ///
  /// This method will return the number of rows deleted.
  /// Example:
  ///
  ///       var q = new Query<User>()
  ///           ..matchOn.id = whereEqualTo(1);
  ///       var deletedCount = await q.delete();
  Future<int> delete() async {
    return await context._executeDeleteQuery(this);
  }
}

/// An exception describing an issue with a query.
///
/// A suggested HTTP status code based on the type of exception will always be available.
class QueryException implements Exception {
  QueryException(this.event,
      {String message: null, this.underlyingException: null})
      : this._message = message;

  final String _message;

  /// The exception generated by the [PersistentStore] or other mechanism that caused [Query] to fail.
  final dynamic underlyingException;

  /// The type of event that caused this exception.
  final QueryExceptionEvent event;

  String toString() => _message ?? underlyingException.toString();
}

/// Categorizations of query failures for [QueryException].
enum QueryExceptionEvent {
  /// This event is used when the underlying [PersistentStore] reports that a unique constraint was violated.
  ///
  /// [RequestController]s interpret this exception to return a status code 409 by default.
  conflict,

  /// This event is used when the underlying [PersistentStore] reports an issue with the form of a [Query].
  ///
  /// [RequestController]s interpret this exception to return a status code 500 by default. This indicates
  /// to the programmer that the issue is with their code.
  internalFailure,

  /// This event is used when the underlying [PersistentStore] cannot reach its database.
  ///
  /// [RequestController]s interpret this exception to return a status code 503 by default.
  connectionFailure,

  /// This event is used when the underlying [PersistentStore] reports an issue with the data used in a [Query].
  ///
  /// [RequestController]s interpret this exception to return a status code 400 by default.
  requestFailure
}

/// Used internally.
abstract class QueryMatchable {
  ManagedEntity entity;

  bool includeInResultSet;

  Map<String, dynamic> get _matcherMap;
}

abstract class _QueryMatchableExtension implements QueryMatchable {
  bool get _hasJoinElements {
    return _matcherMap.values
        .where((item) => item is QueryMatchable)
        .any((QueryMatchable item) => item.includeInResultSet);
  }

  List<String> get _joinPropertyKeys {
    return _matcherMap.keys.where((propertyName) {
      var val = _matcherMap[propertyName];
      var relDesc = entity.relationships[propertyName];

      return val is QueryMatchable &&
          val.includeInResultSet &&
          (relDesc?.relationshipType == ManagedRelationshipType.hasMany ||
              relDesc?.relationshipType == ManagedRelationshipType.hasOne);
    }).toList();
  }
}
