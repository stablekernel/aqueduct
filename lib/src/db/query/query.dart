import 'dart:async';

import '../managed/managed.dart';
import '../postgresql/postgresql_persistent_store.dart';
import '../postgresql/postgresql_query.dart';
import 'matcher_expression.dart';
import 'predicate.dart';

export 'error.dart';
export 'matcher_expression.dart';
export 'predicate.dart';
// This is an unfortunate need because of lack of reified generics
// See factory constructor.

/// Instances of this type configure and execute database commands.
///
/// Queries are used to fetch, update, insert, delete and count objects in a database. A query's [InstanceType] indicates
/// the type of [ManagedObject] subclass' that this query will return as well. The [InstanceType]'s corresponding [ManagedEntity] determines
/// the database table and columns to work with.
///
///         var query = new Query<Employee>()
///           ..where.salary = whereGreaterThan(50000);
///         var employees = await query.fetch();
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

  /// Configures this instance to also include has-one relationship properties for returned objects.
  ///
  /// This method configures this instance to also include values for the relationship property identified
  /// by [propertyIdentifier]. [propertyIdentifier] must return a has-one relationship property of [InstanceType].
  /// i.e., the returned value from this closure must be a [ManagedObject] subclass.
  ///
  ///         var query = new Query<AccountHolder>()
  ///           ..joinOne((accountHolder) => accountHolder.primaryAccount);
  ///
  /// Instances returned from this query when executing [fetch] or [fetchOne]
  /// will include values for that relationship property if a value exists. If the value does not exist,
  /// i.e. the value is null, the returned object will contain the null value for its relationship property.
  ///
  /// This method returns another instance of [Query] with a parametrized type of the related object. The
  /// return query is a subquery of this instance. A subquery may be configured just like any other query,
  /// e.g. configuring properties like [returningProperties] and [where].
  ///
  /// More than one [joinOne] (or [joinMany]) can be used on a single query and subqueries can also have [joinOne]
  /// and [joinMany] nested configurations. Keep in mind, each additional join configuration does have an impact on
  /// query performance.
  ///
  /// This configuration is only valid when executing [fetch] or [fetchOne].
  Query<T> joinOne<T extends ManagedObject>(
      T propertyIdentifier(InstanceType x));

  /// Configures this instance to also include has-many relationship properties for returned objects.
  ///
  /// This method configures this instance to also include values for the relationship property identified
  /// by [propertyIdentifier]. [propertyIdentifier] must return a has-many relationship property of [InstanceType].
  /// i.e., the returned value from this closure must be a [ManagedSet].
  ///
  ///         var query = new Query<AccountHolder>()
  ///           ..joinMany((accountHolder) => accountHolder.accounts);
  ///
  /// Instances returned from this query when executing [fetch] or [fetchOne]
  /// will include values for that relationship property if a value exists. If the value does not exist,
  /// i.e. the value is null, the returned object will contain the null value for its relationship property.
  ///
  /// This method returns another instance of [Query] with a parametrized type of the related object. The
  /// return query is a subquery of this instance. A subquery may be configured just like any other query,
  /// e.g. configuring properties like [returningProperties] and [where].
  ///
  /// More than one [joinOne] (or [joinMany]) can be used on a single query and subqueries can also have [joinOne]
  /// and [joinMany] nested configurations. Keep in mind, each additional join configuration does have an impact on
  /// query performance.
  ///
  /// This configuration is only valid when executing [fetch] or [fetchOne].
  Query<T> joinMany<T extends ManagedObject>(
      ManagedSet<T> propertyIdentifier(InstanceType x));


  /// Configures this instance to fetch a section of a larger result set.
  ///
  /// This method provides an effective mechanism for paging a result set by ordering rows
  /// by some property, offsetting into that ordered set and returning rows starting from that offset.
  /// The [fetchLimit] of this instance must also be configured to limit the size of the page.
  ///
  /// The property that determines order is identified by [propertyIdentifier]. This closure must
  /// return a property of of [InstanceType]. The order is determined by [order]. When fetching
  /// the 'first' page of results, no value is passed for [boundingValue]. As later pages are fetched,
  /// the value of the paging property for the last returned object in the previous result set is used
  /// as [boundingValue]. For example:
  ///
  ///         var recentHireQuery = new Query<Employee>()
  ///           ..pageBy((e) => e.hireDate, QuerySortOrder.descending);
  ///         var recentHires = await recentHireQuery.fetch();
  ///
  ///         var nextRecentHireQuery = new Query<Employee>()
  ///           ..pageBy((e) => e.hireDate, QuerySortOrder.descending,
  ///             boundingValue: recentHires.last.hireDate);
  ///
  /// Note that internally, [pageBy] adds a matcher to [where] and adds a high-priority [sortBy].
  /// Adding multiple [pageBy]s to an instance has undefined behavior.
  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order,
      {T boundingValue});


  /// Configures this instance to sort its results by some property and order.
  ///
  /// This method will have the database perform a sort by some property identified by [propertyIdentifier].
  /// [propertyIdentifier] must return a scalar property of [InstanceType] that can be compared. The [order]
  /// indicates the order the returned rows will be in. Multiple [sortBy]s may be invoked on an instance;
  /// the order in which they are added indicates sort precedence. Example:
  ///
  ///         var query = new Query<Employee>()
  ///           ..sortBy((e) => e.name, QuerySortOrder.ascending);
  void sortBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order);

  /// The [ManagedEntity] of the [InstanceType].
  ManagedEntity get entity;

  /// The [ManagedContext] this query will be executed on.
  ManagedContext get context;

  /// A convenience for building [predicate] in a safe way.
  ///
  /// Use this property instead of providing a [predicate] to filter the rows this query manipulates or fetches. This property
  /// is an instance of [InstanceType] with special [ManagedObject.backingMap] behavior. When you set properties of this property using
  /// matchers (see examples such as [whereEqualTo] and [whereContainsString]), the underlying database will generate a [QueryPredicate] to
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

  /// Configures the list of properties to be fetched for [InstanceType].
  ///
  /// This method configures which properties will be populated for [InstanceType] when returned
  /// from this query. This impacts all query execution methods that return [InstanceType] or [List] of [InstanceType].
  ///
  /// The following example would configure this instance to fetch the 'id' and 'name' for each returned 'Employee':
  ///
  ///         var q = new Query<Employee>()
  ///           ..returningProperties((employee) => [employee.id, employee.name]);
  ///
  /// Note that if the primary key property of an object is omitted from this list, it will be added when this
  /// instance executes. If the primary key value should not be sent back as part of an API response,
  /// it can be stripped from the returned object(s) with [ManagedObject.removePropertyFromBackingMap].
  ///
  /// If this method is not invoked, the properties defined by [ManagedEntity.defaultProperties] are returned.
  void returningProperties(List<dynamic> propertyIdentifiers(InstanceType x));

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

/// Order value for [Query.pageBy] and [Query.sortBy].
enum QuerySortOrder {
  /// Ascending order. Example: 1, 2, 3, 4, ...
  ascending,

  /// Descending order. Example: 4, 3, 2, 1, ...
  descending
}
