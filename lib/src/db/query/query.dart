import 'dart:async';

import '../managed/managed.dart';
import 'predicate.dart';
import 'sort_descriptor.dart';
import 'matcher_expression.dart';

export 'matcher_expression.dart';
export 'predicate.dart';
export 'sort_descriptor.dart';
export 'error.dart';

// This is an unfortunate need because of lack of reified generics
// See factory constructor.
import '../postgresql/postgresql_query.dart';
import '../postgresql/postgresql_persistent_store.dart';

/// Contains information for building and executing a database operation.
///
/// Queries are used to fetch, update, insert, delete and count objects in a database. A query's [InstanceType] indicates
/// the type of [ManagedObject] subclass' that this query will return as well. The [InstanceType]'s corresponding [ManagedEntity] determines
/// the database table and columns to work with.
abstract class Query<InstanceType extends ManagedObject> {
  /// Creates a new [Query].
  ///
  /// By default, [context] is [ManagedContext.defaultContext]. The [entity] of this instance is found by
  /// evaluating [InstanceType] in [context].
  factory Query([ManagedContext context]) {
    var ctx = context ?? ManagedContext.defaultContext;

    // This is an unfortunate need because of lack of reified generics.
    // Would be better if persistent stores had a method to return a Query<T> subclass
    // where T was not stripped.
    if (ctx.persistentStore is PostgreSQLPersistentStore) {
      return new PostgresQuery<InstanceType>(ctx);
    }

    return null;
  }

  Query<T> joinOn<T extends ManagedObject>(T propertyIdentifier(InstanceType x));
  Query<T> joinMany<T extends ManagedObject>(ManagedSet<T> propertyIdentifier(InstanceType x));
  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order, {T boundingValue});

  /// The [ManagedEntity] of the [InstanceType].
  ManagedEntity get entity;

  /// The [ManagedContext] this query will be executed on.
  ManagedContext get context;

  /// A convenience for building [predicate] in a safe way.
  ///
  /// Use this property instead of providing a [predicate] to filter the rows this query manipulates or fetches. This property
  /// is an instance of [InstanceType] with special [ManagedObject.backingMap] behavior. When you set properties of this property using
  /// matchers (see examples such as [whereEqualTo] and [whereContains]), the underlying database will generate a [QueryPredicate] to
  /// match the behavior of these matches. For example, the following query will generate a predicate that only operates on rows
  /// where 'id' is greater than 1:
  ///
  ///       var q = new Query<Employee>()
  ///           ..where.employeeID = greaterThan(1);
  InstanceType get where;


  /// Confirms that a query has no predicate before executing it.
  ///
  /// This is a safety measure for update and delete queries to prevent accidentally updating or deleting every row.
  /// This flag defaults to false, meaning that if this query is either an update or a delete, but contains no predicate,
  /// it will fail. If a query is meant to update or delete every row on a table, you may set this to true to allow this query to proceed.
  bool canModifyAllInstances;

  /// Number of seconds before a Query times out.
  ///
  /// A Query will fail and throw a [QueryException] if [timeoutInSeconds] seconds elapse before the query completes.
  int timeoutInSeconds;

  /// Limits the number of objects returned from the Query.
  ///
  /// Defaults to 0. When zero, there is no limit to the number of objects returned from the Query.
  /// This value should be set when using [pageDescriptor] to limit the page size.
  int fetchLimit;

  /// Offsets the rows returned.
  ///
  /// The set of rows returned will exclude the first [offset] number of rows selected in the query. Do not
  /// set this property when using [pageDescriptor].
  int offset;

  /// The order in which rows should be returned.
  ///
  /// By default, results are not sorted. Sort descriptors are evaluated in order, thus the first sort descriptor
  /// is applies first, the second to break ties, and so on.
  List<QuerySortDescriptor> sortDescriptors;

  /// A predicate for filtering the result or operation set.
  ///
  /// A predicate will identify the rows being accessed, see [QueryPredicate] for more details. Prefer to use
  /// [where] instead of this property directly.
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
  InstanceType values;

  /// A list of properties to be fetched by this query.
  ///
  /// Each [InstanceType] will have these properties set when this query is executed. Each property must be
  /// a column-backed property of [InstanceType].
  ///
  /// By default, this property is null, which indicates that the default properties of [InstanceType] should be fetched.
  /// See [ManagedEntity.defaultProperties] for more details.
  List<String> propertiesToFetch;

  /// Inserts an [InstanceType] into the underlying database.
  ///
  /// The [Query] must have its [values] or [valueMap] property set. This operation will
  /// insert a row with the data supplied in those fields to the database in [context]. The return value is
  /// a [Future] that completes with the newly inserted [InstanceType]. Example:
  ///
  ///       var q = new Query<User>()
  ///         ..values.name = "Joe";
  ///       var newUser = await q.insert();
  Future<InstanceType> insert();

  /// Updates [InstanceType]s in the underlying database.
  ///
  /// The [Query] must have its [values] or [valueMap] property set and should likely have its [predicate] or [where] set as well. This operation will
  /// update each row that matches the conditions in [predicate]/[where] with the values from [values] or [valueMap]. If no [where] or [predicate] is set,
  /// this method will throw an exception by default, assuming that you don't typically want to update every row in a database table. To specify otherwise,
  /// set [canModifyAllInstances] to true.
  /// The return value is a [Future] that completes with the any updated [InstanceType]s. Example:
  ///
  ///       var q = new Query<User>()
  ///         ..where.name = "Fred"
  ///         ..values.name = "Joe";
  ///       var usersNamedFredNowNamedJoe = await q.update();
  Future<List<InstanceType>> update();

  /// Updates an [InstanceType] in the underlying database.
  ///
  /// This method works the same as [update], except it may only update one row in the underlying database. If this method
  /// ends up modifying multiple rows, an exception is thrown.
  Future<InstanceType> updateOne();

  /// Fetches [InstanceType]s from the database.
  ///
  /// This operation will return all [InstanceType]s from the database, filtered by [predicate]/[where]. Example:
  ///
  ///       var q = new Query<User>();
  ///       var allUsers = q.fetch();
  ///
  Future<List<InstanceType>> fetch();

  /// Fetches a single [InstanceType] from the database.
  ///
  /// This method behaves the same as [fetch], but limits the results to a single object.
  Future<InstanceType> fetchOne();

  /// Deletes [InstanceType]s from the underlying database.
  ///
  /// This method will delete rows identified by [predicate]/[where]. If no [where] or [predicate] is set,
  /// this method will throw an exception by default, assuming that you don't typically want to delete every row in a database table. To specify otherwise,
  /// set [canModifyAllInstances] to true.
  ///
  /// This method will return the number of rows deleted.
  /// Example:
  ///
  ///       var q = new Query<User>()
  ///           ..where.id = whereEqualTo(1);
  ///       var deletedCount = await q.delete();
  Future<int> delete();
}
