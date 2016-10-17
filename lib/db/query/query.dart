part of aqueduct;

/// An representation of a database operation.
///
/// Queries are used to find, update, insert, delete and count objects in a database.
class Query<InstanceType extends ManagedObject> {
  Query({this.context}) {
    context ??= ManagedContext.defaultContext;
    entity = context.dataModel.entityForType(InstanceType);
  }

  ManagedEntity entity;
  ManagedContext context;

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
  /// This is a safety measure for update and delete queries. This flag defaults to false, meaning that if this query is
  /// either an update or a delete, but contains no predicate, it will fail. If a query is meant to update or delete every
  /// row on a table, you may set this to true to allow this query to proceed.
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate = false;

  ///
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
  List<QuerySortDescriptor> sortDescriptors;

  /// A predicate for filtering the result or operation set.
  ///
  /// A predicate will identify the rows being accessed, see [QueryPredicate] for more details.
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

  /// A list of properties to be returned by the Query.
  ///
  /// By default, [resultProperties] is null and therefore all objects returned will contain all properties
  /// of the object. (Unless those properties are marked as hasOne or hasMany relationships.) Specifying
  /// an explicit list of keys will return only those properties. Keys must match the names of the properties
  /// in of [InstanceType].
  List<String> resultProperties;

  Map<Type, List<String>> nestedResultProperties = {};

  /// Inserts the data represented by this Query into the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// The [Query] must have its [values] or [valueMap] property set. This action method will
  /// insert a row with the data supplied in those fields to the database represented by [context]. The return value is
  /// a [Future] with the inserted object. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.values.name = "Joe";
  ///       var newUser = await q.insert();
  ///
  Future<InstanceType> insert() async {
    return await context._executeInsertQuery(this);
  }

  /// Updates rows in the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// Update queries update the values of the rows identified by [predicate]
  /// with the values in [values] or [valueMap] in the database represented by [context]. Example:
  ///
  ///       var existingUser = ...;
  ///       existingUser.name = "Bob";
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : existingUser.id});
  ///       q.values = existingUser;
  ///       var updatedUsers = await q.update();
  Future<List<InstanceType>> update() async {
    return await context._executeUpdateQuery(this);
  }

  /// Updates a row in the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// Update queries update the values of the rows identified by [predicate]
  /// with the values in [values] or [valueMap] in the database represented by [context]. Example:
  ///
  ///       var existingUser = ...;
  ///       existingUser.name = "Bob";
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : existingUser.id});
  ///       q.values = existingUser;
  ///       var updatedUsers = await q.update();
  Future<InstanceType> updateOne() async {
    var results = await context._executeUpdateQuery(this);
    if (results.length == 1) {
      return results.first;
    } else if (results.length == 0) {
      return null;
    }

    throw new QueryException(QueryExceptionEvent.internalFailure, message: "updateOne modified more than one row, this is a serious error.");
  }

  /// Fetches rows in the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// Fetch queries will return objects for the rows identified by [predicate] from
  /// the database represented by [context]. Example:
  ///
  ///       var q = new Query<User>();
  ///       var allUsers = q.fetch();
  ///
  Future<List<InstanceType>> fetch() async {
    return await context._executeFetchQuery(this);
  }

  /// Fetches a single object from the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// This method will return a single object identified by [predicate] from
  /// the database represented by [context]. If no match is found, this method returns [null].
  /// If more than one match is found, this method throws an exception. Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var user = await q.fetchOne();
  Future<InstanceType> fetchOne() async {
    fetchLimit = 1;

    var results = await context._executeFetchQuery(this);
    if (results.length == 1) {
      return results.first;
    } else if (results.length > 1) {
      throw new QueryException(QueryExceptionEvent.requestFailure, message: "Query expected to fetch one instance, but ${results.length} instances were returned.");
    }
    return null;
  }

  /// Deletes rows from the database represented by [context] (defaults to [ManagedContext.defaultContext]).
  ///
  /// This method will delete rows identified by [predicate]
  /// from the database represented by [context] and returns the number of rows affected.
  /// Example:
  ///
  ///       var q = new Query<User>();
  ///       q.predicate = new Predicate("id = @id", {"id" : 1});
  ///       var deleted = await q.delete();
  ///
  Future<int> delete() async {
    return await context._executeDeleteQuery(this);
  }
}

/// An exception describing an issue with a query.
///
/// A suggested HTTP status code based on the type of exception will always be available.
class QueryException implements Exception {
  QueryException(this.event, {String message: null, this.underlyingException: null}) :
      this._message = message;

  final String _message;
  final dynamic underlyingException;
  final QueryExceptionEvent event;

  String toString() => _message ?? underlyingException.toString();
}

enum QueryExceptionEvent {
  conflict,
  internalFailure,
  connectionFailure,
  requestFailure
}

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

      return val is QueryMatchable
          && val.includeInResultSet
          && (relDesc?.relationshipType == ManagedRelationshipType.hasMany || relDesc?.relationshipType == ManagedRelationshipType.hasOne);
    }).toList();
  }
}