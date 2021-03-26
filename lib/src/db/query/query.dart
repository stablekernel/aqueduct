import 'dart:async';

import '../managed/managed.dart';
import 'error.dart';
import 'matcher_expression.dart';
import 'predicate.dart';
import 'reduce.dart';

export 'error.dart';
export 'matcher_expression.dart';
export 'predicate.dart';
export 'reduce.dart';

/// An object for configuring and executing a database query.
///
/// Queries are used to fetch, update, insert, delete and count [InstanceType]s in a database.
/// [InstanceType] must be a [ManagedObject].
///
///         final query = Query<Employee>()
///           ..where((e) => e.salary).greaterThan(50000);
///         final employees = await query.fetch();
abstract class Query<InstanceType extends ManagedObject> {
  /// Creates a new [Query].
  ///
  /// The query will be sent to the database described by [context].
  /// For insert or update queries, you may provide [values] through this constructor
  /// or set the field of the same name later. If set in the constructor,
  /// [InstanceType] is inferred.
  factory Query(ManagedContext context, {InstanceType values}) {
    final entity = context.dataModel.entityForType(InstanceType);
    if (entity == null) {
      throw ArgumentError(
          "Invalid context. The data model of 'context' does not contain '$InstanceType'.");
    }

    return context.persistentStore.newQuery<InstanceType>(context, entity, values: values);
  }

  /// Creates a new [Query] without a static type.
  ///
  /// This method is used when generating queries dynamically from runtime values,
  /// where the static type argument cannot be defined. Behaves just like the unnamed constructor.
  ///
  /// If [entity] is not in [context]'s [ManagedContext.dataModel], throws a internal failure [QueryException].
  factory Query.forEntity(ManagedEntity entity, ManagedContext context) {
    if (!context.dataModel.entities.any((e) => identical(entity, e))) {
      throw StateError(
          "Invalid query construction. Entity for '${entity.tableName}' is from different context than specified for query.");
    }

    return context.persistentStore.newQuery<InstanceType>(context, entity);
  }

  /// Inserts a single [object] into the database managed by [context].
  ///
  /// This is equivalent to creating a [Query], assigning [object] to [values], and invoking [insert].
  static Future<T> insertObject<T extends ManagedObject>(
      ManagedContext context, T object) {
    return context.insertObject(object);
  }

  /// Inserts each object in [objects] into the database managed by [context] in a single transaction.
  ///
  /// This currently has no Query instance equivalent
  static Future<List<T>> insertObjects<T extends ManagedObject>(
      ManagedContext context, List<T> objects) async {
    return context.insertObjects(objects);
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
  ///         var query = Query<User>()
  ///           ..join(object: (u) => u.profile);
  ///
  /// To fetch an object and its has-many properties, use the [set] closure:
  ///
  ///         var query = Query<User>()
  ///           ..join(set: (u) => u.notes);
  ///
  /// Both [object] and [set] are passed an empty instance of the type being queried. [object] must return a has-one property (a [ManagedObject] subclass)
  /// of the object it is passed. [set] must return a has-many property (a [ManagedSet]) of the object it is passed.
  ///
  /// Multiple relationship properties can be included by invoking this method multiple times with different properties, e.g.:
  ///
  ///         var query = Query<User>()
  ///           ..join(object: (u) => u.profile)
  ///           ..join(set: (u) => u.notes);
  ///
  /// This method also returns a new instance of [Query], where [InstanceType] is is the type of the relationship property. This can be used
  /// to configure which properties are returned for the related objects and to filter a [ManagedSet] relationship property. For example:
  ///
  ///         var query = Query<User>();
  ///         var subquery = query.join(set: (u) => u.notes)
  ///           ..where.dateCreatedAt = whereGreaterThan(someDate);
  ///
  /// This mechanism only works on [fetch] and [fetchOne] execution methods. You *must not* execute a subquery created by this method.
  Query<T> join<T extends ManagedObject>(
      {T object(InstanceType x), ManagedSet<T> set(InstanceType x)});

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
  ///         var recentHireQuery = Query<Employee>()
  ///           ..pageBy((e) => e.hireDate, QuerySortOrder.descending);
  ///         var recentHires = await recentHireQuery.fetch();
  ///
  ///         var nextRecentHireQuery = Query<Employee>()
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
  ///         var query = Query<Employee>()
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
  ///         var query = Query<User>();
  ///         var averageAge = await query.reduce.average((user) => user.age);
  ///
  /// Any where clauses established by [where] or [predicate] will impact the rows evaluated
  /// and therefore the value returned from this object's instance methods.
  ///
  /// Always returns a new instance of [QueryReduceOperation]. The returned object is permanently
  /// associated with this instance. Any changes to this instance (i.e., modifying [where]) will impact the
  /// result.
  QueryReduceOperation<InstanceType> get reduce;

  /// Selects a property from the object being queried to add a filtering expression.
  ///
  /// You use this property to add filtering expression to a query. The expressions are added to the SQL WHERE clause
  /// of the generated query.
  ///
  /// You provide a closure for [propertyIdentifier] that returns a property of its argument. Its argument is always
  /// an empty instance of the object being queried. You invoke methods like [QueryExpression.lessThan] on the
  /// object returned from this method to add an expression to this query.
  ///
  ///         final query = Query<Employee>()
  ///           ..where((e) => e.name).equalTo("Bob");
  ///
  /// You may select properties of relationships using this method.
  ///
  ///         final query = Query<Employee>()
  ///           ..where((e) => e.manager.name).equalTo("Sally");
  ///
  QueryExpression<T, InstanceType> where<T>(
      T propertyIdentifier(InstanceType x));

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
  /// This method is an unsafe version of [values]. Prefer to use [values] instead.
  /// Keys in this map must be the name of a property of [InstanceType], otherwise an exception
  /// is thrown. Values provided in this map are not run through any [Validate] annotations
  /// declared by the [InstanceType].
  ///
  /// Do not set this property and [values] on the same query. If both this property and [values] are set,
  /// the behavior is undefined.
  Map<String, dynamic> valueMap;

  /// Values to be sent to database during an [update] or [insert] query.
  ///
  /// You set values for the properties of this object to insert a row or update one or more rows.
  /// This property is the same type as the type being inserted or updated. [values] is empty (but not null)
  /// when a [Query] is first created, therefore, you do not have to assign an instance to it and may set
  /// values for its properties immediately:
  ///
  ///         var q = Query<User>()
  ///           ..values.name = 'Joe'
  ///           ..values.job = 'programmer';
  ///         await q.insert();
  ///
  /// You may only set values for properties that are backed by a column. This includes most properties, except
  /// all [ManagedSet] properties and [ManagedObject] properties that do not have a [Relate] annotation. If you attempt
  /// to set a property that isn't allowed on [values], an error is thrown.
  ///
  /// If a property of [values] is a [ManagedObject] with a [Relate] annotation, you may provide a value for its primary key
  /// property. This value will be stored in the foreign key column that backs the property. You may set properties
  /// of this type immediately, without having to create an instance of the related type:
  ///
  ///         // Assumes that Employee is declared with the following property:
  ///         // @Relate(#employees)
  ///         // Manager manager;
  ///
  ///         final q = Query<Employee>()
  ///           ..values.name = "Sally"
  ///           ..values.manager.id = 10;
  ///         await q.insert();
  ///
  /// WARNING: You may replace this property with a new instance of [InstanceType]. When doing so, a copy
  /// of the object is created and assigned to this property.
  ///
  ///         final o = SomeObject()
  ///           ..id = 1;
  ///         final q = Query<SomeObject>()
  ///           ..values = o;
  ///
  ///         o.id = 2;
  ///         assert(q.values.id == 1); // true
  ///
  InstanceType values;

  /// Configures the list of properties to be fetched for [InstanceType].
  ///
  /// This method configures which properties will be populated for [InstanceType] when returned
  /// from this query. This impacts all query execution methods that return [InstanceType] or [List] of [InstanceType].
  ///
  /// The following example would configure this instance to fetch the 'id' and 'name' for each returned 'Employee':
  ///
  ///         var q = Query<Employee>()
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
  ///       var q = Query<User>()
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
  ///       var q = Query<User>()
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
  ///       var q = Query<User>();
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
  ///       var q = Query<User>()
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
