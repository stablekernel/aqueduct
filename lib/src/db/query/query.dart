import 'dart:async';

import '../managed/managed.dart';

import 'matcher_expression.dart';
import 'predicate.dart';
import 'error.dart';
import 'reduce.dart';

export 'error.dart';
export 'matcher_expression.dart';
export 'predicate.dart';
export 'reduce.dart';


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
    var entity = ctx.dataModel.entityForType(InstanceType);

    return ctx.persistentStore.newQuery<InstanceType>(ctx, entity);
  }

  /// Creates a new [Query] without a static type.
  ///
  /// This method is used when generating queries dynamically from runtime values,
  /// where the static type argument cannot be defined. Behaves just like the unnamed constructor.
  ///
  /// If [entity] is not in [context]'s [ManagedContext.dataModel], throws a internal failure [QueryException].
  factory Query.forEntity(ManagedEntity entity, [ManagedContext context]) {
    var ctx = context ?? ManagedContext.defaultContext;
    if (!ctx.dataModel.entities.any((e) => identical(entity, e))) {
      throw new StateError("Invalid query construction. Entity for '${entity.tableName}' is from different context than specified for query.");
    }

    return ctx.persistentStore.newQuery<InstanceType>(ctx, entity);
  }

  /// Configures this instance to fetch a relationship property identified by [object] or [set].
  ///
  /// By default, objects returned by [Query.fetch] do not have their relationship properties populated. (In other words,
  /// [ManagedObject] and [ManagedSet] properties are null.) This method configures this instance to conduct a SQL join,
  /// allowing it to fetch relationship properties for the returned instances.
  ///
  /// Consider a [ManagedObject] subclass with the following relationship properties as an example:
  ///
  ///         class User extends ManagedObject<_User> implements _User {}
  ///         class _User {
  ///           Profile profile;
  ///           ManagedSet<Note> notes;
  ///         }
  ///
  /// To fetch an object and one of its has-one properties, use the [object] closure:
  ///
  ///         var query = new Query<User>()
  ///           ..join(object: (u) => u.profile);
  ///
  /// To fetch an object and its has-many properties, use the [set] closure:
  ///
  ///         var query = new Query<User>()
  ///           ..join(set: (u) => u.notes);
  ///
  /// Both [object] and [set] are passed an empty instance of the type being queried. [object] must return a has-one property (a [ManagedObject] subclass)
  /// of the object it is pased. [set] must return a has-many property (a [ManagedSet]) of the object it is passed.
  ///
  /// Multiple relationship properties can be included by invoking this method multiple times with different properties, e.g.:
  ///
  ///         var query = new Query<User>()
  ///           ..join(object: (u) => u.profile)
  ///           ..join(set: (u) => u.notes);
  ///
  /// This method also returns a new instance of [Query], where [InstanceType] is is the type of the relationship property. This can be used
  /// to configure which properties are returned for the related objects and to filter a [ManagedSet] relationship property. For example:
  ///
  ///         var query = new Query<User>();
  ///         var subquery = query.join(set: (u) => u.notes)
  ///           ..where.dateCreatedAt = whereGreaterThan(someDate);
  ///
  /// This mechanism only works on [fetch] and [fetchOne] execution methods. You *must not* execute a subquery created by this method.
  Query<T> join<T extends ManagedObject>({T object(InstanceType x), ManagedSet<T> set(InstanceType x)});

  /// Deprecated: see [join].
  @Deprecated("3.0, use join(object:set:) instead")
  Query<T> joinOne<T extends ManagedObject>(
      T propertyIdentifier(InstanceType x));

  /// Deprecated: see [join].
  @Deprecated("3.0, use join(object:set:) instead")
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

  /// Returns a new object that can execute functions like sum, average, maximum, etc.
  ///
  /// The methods of this object will execute an aggregate function on the database table.
  /// For example, this property can be used to find the average age of all users.
  ///
  ///         var query = new Query<User>();
  ///         var averageAge = await query.reduce.average((user) => user.age);
  ///
  /// Any where clauses established by [where] or [predicate] will impact the rows evaluated
  /// and therefore the value returned from this object's instance methods.
  ///
  /// Always returns a new instance of [QueryReduceOperation]. The returned object is permanently
  /// associated with this instance. Any changes to this instance (i.e., modifying [where]) will impact the
  /// result.
  QueryReduceOperation<InstanceType> get reduce;

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
  /// This value should be set when using [pageBy] to limit the page size.
  int fetchLimit;

  /// Offsets the rows returned.
  ///
  /// The set of rows returned will exclude the first [offset] number of rows selected in the query. Do not
  /// set this property when using [pageBy].
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
  ///
  /// If the [InstanceType] has properties with [Validate] metadata, those validations
  /// will be executed prior to sending the query to the database.
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
  ///
  /// If the [InstanceType] has properties with [Validate] metadata, those validations
  /// will be executed prior to sending the query to the database.
  Future<List<InstanceType>> update();

  /// Updates an [InstanceType] in the underlying database.
  ///
  /// This method works the same as [update], except it may only update one row in the underlying database. If this method
  /// ends up modifying multiple rows, an exception is thrown.
  ///
  /// If the [InstanceType] has properties with [Validate] metadata, those validations
  /// will be executed prior to sending the query to the database.
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
