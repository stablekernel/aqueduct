---
layout: page
title: "Executing Queries"
category: db
date: 2016-06-20 10:35:56
order: 5
---

## Query<T> Instances Send Commands to a Database

To send commands to a database - whether to fetch, insert, delete or update objects - you will create, configure and execute instances of `Query<T>`. A `Query<T>` allows you to create database operations in Dart code in the domain of your application, as opposed to writing SQL. `Query<T>`s are executed against a `ManagedContext`. By default, every `Query<T>` uses `ManagedContext.defaultContext`, but this can be changed during the instantiation of a `Query<T>`.

(Note that raw SQL may be sent to a database in an Aqueduct application using instances of `PersistentStore` directly. Queries are meant for typical data operations. Tasks such as schema management, or queries that require special optimization are the typical reasons to write SQL directly using `execute` or `Query<T>` on the `PersistentStore`).

Instances of `Query<T>` are generic. The type parameter indicates the `ManagedObject<T>` subclass you are fetching, inserting, deleting or updating. When a `Query<T>` is created, it sets its `entity` property to `ManagedEntity` that represents its type parameter. It uses this information to validate and build queries.

```dart
var query = new Query<User>();

query.entity.instanceType; // -> ClassMirror on 'User'
```

A `Query<T>` has four basic execution methods: `fetch`, `update`, `insert`, `delete`. These methods will perform a database operation based on the information configured in the `Query<T>`.

* `fetch` will retrieve data from a database (it is equivalent to the SQL operation `SELECT`). Rows are returned in instances of the `Query<T>`'s generic type.
* `update` will modify existing data in a database (it is equivalent to the SQL operation `UPDATE`). Rows are returned in instances of the `Query<T>`'s generic type.
* `insert` will add new data to a database (it is equivalent to the SQL operation `INSERT`). Rows are returned in instances of the `Query<T>`'s generic type.
* `delete` will remove data from a database (it is equivalent to the SQL operation `DELETE`). The number of rows deleted is returned as an integer.

A `Query<T>` has properties that dictate the information that will be used in their execution methods. These properties will impact which objects get fetched, the data that gets sent to the database, the order that data is returned in, and so on. A `Query<T>` is not instantiated with a pre-determined execution method; the same `Query<T>` can be used to `fetch` objects and then used to `delete` objects without any changes. The `Query<T>` does not maintain any state about execution methods executed or results from an execution of it.

### Inserting Data with a Query

To configure a query to insert an object into a database, you must first create an instance of `Query<T>`. To specify the values to insert, every `Query<T>` has a `values` properties. Setting values in this instance configures the values the `Query<T>` will insert when it is executed. For example, if there was a `User` entity with a `name` and `email`, you would configure a `Query<T>` to insert an instance of `User` like so:

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  
```

The `values` property of a `Query<T>` will automatically be created as soon as you access it. You may also provide an instance to `values` directly; this comes in handy when you are getting an object from an HTTP request body:

```dart
var user = new User()
  ..readMap(requestBody);

var query = new Query<User>()
  ..values = user;
```

(You may optionally configure a `Query<T>`'s `valueMap` to supply values for an insert query, but this is less desirable because `valueMap` is stringly-typed whereas `values` is both key-checked and type-checked. You may only use one or the other. If both `valueMap` and `values` are configured, the `Query<T>`'s behavior is undefined.)

Once a `Query<T>` has been configured with values, it may be executed as an insert command. The value returned from an insert will be the newly inserted instance inside a `Future<T>`.

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  

var user = await query.insert();
user.name; // "Bob"
user.email; // "bob@stablekernel.com"
user.id; // 1
```

Since most managed objects have an auto-incrementing primary key, it is important to get the returned object from an insert execution, as it will contain the generated primary key value.

Note that only the data explicitly set in `values` (or `valueMap`) is sent to the database. Unset values are *not* sent as `null` and entirely omitted from the insert command. Values that are set explicitly as `null` will set the value to `null` in the database.

```dart
var query = new Query<User>()
  ..values.name = "Bob";
await query.insert(); // WILL NOT set email of User.

var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = null;
await query.insert(); // WILL set email of User to null.
```

If an insert query fails because of a conflict - a unique constraint is violated - Aqueduct will automatically generate a `QueryException` that a `RequestController` will translate to a 409 status code. This default behavior means that you don't have to check for the specific error of unique constraint violation and Aqueduct will abandon execution and return a 409 'Conflict' response to the calling client.

### Updating Data with a Query

Updating data with a `Query<T>` is similar to inserting data in that the data you set the `values` of a `Query<T>` for data you want to change. The type parameter for the `Query<T>` indicates which entity - and therefore which database table - will get updated when the query is executed.

An update query can - and likely should - be restricted to a single row or subset of rows. This is done by using the `matchOn` property of a `Query<T>` - which gets translated into the *where clause* of the underlying SQL statement.

Because `Query<T>.matchOn` can be used for update, fetch and delete queries, and they are such a large topic, there is a separate section reserved specifically for those properties. For the purpose of understanding update queries, know that the `matchOn` properties allow you to identify specific rows in a database for which to carry out the query's operation.

By executing an update query, the specified rows will get new values for all of the values in `values` (or `valueMap`). Only the `values` explicitly specified in the query will be modified by the update query. In effect, this means you do not have to fetch an object before updating it - you can provide only the values you wish to update and the remainder of the row is unmodified.

```dart
// A Query that will change any user's whose name is 'Bob' to 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..matchOn.name = whereEqualTo("Bob");

List<User> bobsThatAreNowFreds = await query.update();
```

An update query returns every modified row as a result, returning them as instances the appropriate `ManagedObject<T>` subclass. Only rows that were updated will be returned and they will be returned as instances of the appropriate `ManagedObject<T>` subclass. There is a variant to `Query<T>.update` named `updateOne`. The `updateOne` method will build and execute a SQL query in the same way a normal `update` does, however, it will return you a single instance that was updated instead of a list. This is convenience method for the caller to get back a single instance instead of a list:

```dart
// Update user with id = 1 to have the name 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..matchOn.id = whereEqualTo(1);

var updatedUser = await query.updateOne();
```

The `updateOne` method will return `null` if no rows were updated. It is important to note that if `updateOne` is used and more than one row is updated, `updateOne` will throw an exception and the changes to the data *are not reversible*. Because this is likely a mistake, this is considered an error, hence the exception is thrown. It is up to the programmer to recognize whether or not a particular `updateOne` query would impact multiple rows.

If an update violates a unique property, a `QueryException` will be thrown with `QueryExceptionEvent.conflict` as its `event`. A `RequestController` will respond to a request with a status code 409 when this exception is bubbled up to its exception handler.

Update queries have a safety feature that prevents you from accidentally updating every row. If you try to execute a `Query<T>` to do an update and no `predicate` or `matchOn` property is defined, the default behavior of `Query<T>` will throw an exception prior to carrying out the request. If you explicitly want to update every instance of some entity (that is, every row of a table), you must set the `Query<T>`'s `confirmQueryModifiesAllInstancesOnDeleteOrUpdate` to `true` prior to execution. (This property defaults to `false`.)

### Deleting Data with a Query

A delete `Query<T>` will delete rows from a database for the entity specified by its type argument. Like update and fetch queries, you may specify a row or rows using `matchOn` properties of the `Query<T>`. The result of a delete operation will be a `Future<int>` with the number of rows deleted.

```dart
var query = new Query<User>()
  ..matchOn.id = 1;

int usersDeleted = await query.delete();
```

Also like update queries, delete queries have a safety feature that prevents you from accidentally deleting every row in a table with `confirmQueryModifiesAllInstancesOnDeleteOrUpdate`.

Any properties set in the query's `values` or `valueMap` are ignored when executing a delete.

### Fetching Data with a Query

Of the four basic operations of a `Query<T>`, fetching data is the most configurable and powerful. In its simplest form, a fetch query will return matching instances for an entity (that is, matching rows from a table). A simple `Query<T>` that would fetch every instance of some entity looks like this:

```dart
var query = new Query<User>();

List<User> allUsers = await query.fetch();
```

A fetch `Query<T>` uses its `matchOn` property to filter the result set, just like delete and update queries. Any properties set in the query's `values` or `valueMap` are ignored when executing a fetch. In addition to fetching a list of instances from a database, you may also fetch a single instance with `fetchOne`. If no instance is found, `null` is returned. (If more than one instance is found, an exception is thrown.)

```dart
var query = new Query<User>()
  ..matchOn.id = 1;

User oneUser = await query.fetchOne();
```

Fetches can be limited to a number of instances by setting the `fetchLimit` property of a `Query<T>`. You may also set the `offset` of a `Query<T>` to skip the first `offset` number of rows. Between `fetchLimit` and `offset`, you can implement naive paging. However, this type of paging suffers from a number of problems and so there is a built-in paging mechanism covered in a later section.

Results of a fetch can be sorted by adding `QuerySortDescriptor`s to `Query<T>.sortDescriptors` property. A `QuerySortDescriptor` has a key (the name of a property on a managed object) and the order in which rows should be sorted (ascending or descending). For example, the following would return users in alphabetical order based on their name, from A-Z:

```dart
var query = new Query<User>()
  ..sortDescriptors = [new QuerySortDescriptor("name", QuerySortOrder.ascending)];

List<User> orderedUsers = await query.fetch();
```

A `Query<T>` can have multiple sort descriptors. Subsequent sort descriptors are used to break ties in previous sort descriptors. The order sort descriptors are applied in is the order they are listed in the `sortDescriptors` list.

Fetch queries can fetch relationships (these are carried out as *database joins* by the `PersistentStore`). Because this is a more complex topic, this discussion is reserved for a later section.

### Specifying Result Properties

When executing a query that returns managed objects (i.e., insert, update and fetch queries), you may configure which properties are actually fetched for each instance. Every entity has a set of `defaultProperties`. If you do not specify exactly which properties to be fetched, fetched instance will contain their `ManagedEntity.defaultProperties`.

The default properties of a managed object are all attributes declared in the persistent type where `ManagedColumnAttributes.omitByDefault` is false and all `ManagedRelationship` properties. (In other words, every actual column on the corresponding database table that you haven't specifically marked to be ignored.) Transient properties are never included in `defaultProperties`, as they are not actually fetched from a database.

Properties like a hashed password and salt are likely candidates to be marked as `omitByDefault`, as you don't typically want to return that information in an HTTP response body. Marking a attribute as such frees you from having to exclude it each time you fetch objects with a `Query<T>`.

If you wish to specify which properties are fetched into an instance when performing a `Query<T>`, you may set the `Query<T>`'s `resultProperties`. This `List<String>` is the name of each property you wish to be fetched. This list is the exact set of properties to be fetched - it does not also include properties from an entity's `defaultProperties`. This property is useful when you want to limit the properties fetched from a query. (Bear in mind, an un-fetched property will be omitted from the `Map` when serialized.) Additionally, setting the `resultProperties` of a `Query<T>` is the only way to fetch properties that are marked as `omitByDefault`.

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @managedPrimaryKey int id;

  String name;
  String gender;

  @ManagedColumnAttributes(unique: true, indexed: true)
  String email;

  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;

  @ManagedColumnAttributes(omitByDefault: true)
  String salt;
}

var query = new Query<User>()
  ..resultProperties = ["id", "email", "hashedPassword", "salt"]
  ..matchOn.email = whereEqualTo("bob@stablekernel.com");

var bob = await query.fetchOne();
bob.backingMap == {
  "id" : 1,
  "email" : "bob@stablekernel.com",
  "hashedPassword" : "ABCD1234ABCD",
  "salt" : "ABCD4321"
};
```

If you specify a property that doesn't exist for a managed object in `resultProperties`, you will get an exception when the `Query<T>` is executed.

You may not add a 'has-many' or 'has-one' relationship to `resultProperties`, as this mechanism is achieved by other functionality on a `Query<T>`. If you do add a 'has-one' or 'has-many' relationship property name to the list of `resultProperties`, an exception will be thrown when the query is executed.

Note that if you omit the primary key of a managed object from `resultProperties`, it will automatically be added.

### Paging Fetched Result Sets

In larger data sets, it may make sense to only return a portion of rows from a database. For example, in a social media application, a user could have thousands of pieces of content they had created over many years. The likely use case for fetching their content would be to grab only the most recent content, and only grab earlier content as necessary. There are many ways to accomplish paging, and the right solution oftentimes depends on the context and may require additional services beyond just a single database - Aqueduct doesn't pretend to fully solve this problem. Aqueduct does provide two mechanisms on `Query<T>` instances for building queries that can fetch a subset of rows within a certain range.

First, naive paging can be accomplished using the `fetchLimit` and `offset` properties of a `Query<T>`. For example, if a table contains 100 rows, and you would like to vend them out 10 at a time to a client, each query would have a value of 10 for its `fetchLimit`. The first query would have an `offset` of 0, then 10, then 20, and so on. Especially when adding `sortDescriptors` to a `Query<T>`, this type of paging can be effective. One of the drawbacks to this type of paging is that it can skip or duplicate rows if rows are being added or deleted while fetching subsequent pages.

For example, a table contains 100 rows and you're fetching ten at a time. After two queries, you've fetched 20 total. The next query will fetch rows 21-30. If before that query goes off, a new row is inserted at row 10, the rest of the rows get shifted upwards. That means the row that was previously at row 20 moves to row 21. When the third query runs, it'll get that row again. Likewise, if a row is deleted from within the first 20 rows, what would have been row 21 moves into slot 20. The third query won't get that row and it is effectively skipped.

A `Query<T>` has a property named `pageDescriptor` (an instance of `QueryPage`) to better handle paging and avoid the problem of sliding rows. A `QueryPage` works by sorting a table by one of its columns and finding a point in the sorted rows where one row is less than a value and the next row is greater than that value. When a fetch is made with a query page, the first row is fetched from one side of that pivot point. This value is called the `boundingValue`. The number of rows fetched is determined by `Query.fetchLimit`.

For example, consider an entity that has a `createdDate` property:

```dart
class Task extends ManagedObject<_Task> implements _Task {}
class _Task {
  @managedPrimaryKey int id;
  String text;

  @ManagedColumnAttributes(indexed: true)
  DateTime dateCreated;
}
```

In an application that displays a timeline of `Task`s, a user would most likely want to see their most recent five tasks first. Then, if they choose to continue browsing, the next five tasks after that, and then the next five and so on. This particular query would fetch the first five `Task`s:

```dart
var query = new Query<Task>()
  ..fetchLimit = 5
  ..pageDescriptor = new QueryPage(SortOrder.descending, "dateCreated");
var firstFive = await query.fetch();
```

The page descriptor here sorts the task table by its `dateCreated` in a descending order - later dates come first. Because no `boundingValue` is specified (`null`) in the `QueryPage`, the values will be fetched from the beginning: the most five most recent task. To fetch the next page, you use a `boundingValue` of the last fetched task's `dateCreated`.

```dart
var firstFive = await query.fetch();

var nextPageQuery = new Query<Task>()
  ..fetchLimit = 5
  ..pageDescriptor = new QueryPage(SortOrder.descending, "dateCreated", boundingValue: firstFive.last.dateCreated);
var nextFive = await nextPageQuery.fetch();  
```

The `boundingValue` is *not* inclusive. For example, if the last task was on October 5, 2013 - the `boundingValue` - the first result of the next page will start at the task that is closest to October 5, 2013 followed by the next four most recent. The `boundingValue` is encoded according to the type of the query page's property when sent to the underlying database, so you may pass normal Dart types like `DateTime` and `int`. The order of the rows returned by a query that has been paged will always match the order defined by the `QueryPage`'s `order`. If the query finds no more instances - that is, it runs out of data - the query will simply return no more objects.

The value `null` should be the `boundingValue` when fetching the first page. It is also permissible to use a value that is known to be well outside of the range of possible values - for example, a date in the year 3000 is unlikely to exclude the most recent task object. It is a good idea to add an index `ColumnAttributes` to any property that is used in a `QueryPage`. Do not use the `offset` property of a `Query<T>` when performing pages, as the property and bounding value already provide an offset into the data.

### Filtering Results of a Fetch Operation

More often than not, fetching every row of a table doesn't make sense. Instead, the desired result is a specific object or set of objects matching some condition. Aqueduct offers two ways to perform this filtering, both of which translate to a SQL *where clause*.

The first option is the least prohibitive, the most prone to error and the most difficult to maintain: a `Query<T>.predicate`. A `Predicate` is a `String` that is added to the underlying query's where clause. A `Predicate` has two properties, a `format` string and a `Map<String, dynamic>` of parameter values. The `format` string can (and should) parameterize any input values. Parameters are indicated in the format string using the `@` token:

```dart
// Creates a predicate that would only include instances where some column "id" is less than 2
var predicate = new Predicate("id < @id", {"id" : 2});
```

The text following the `@` token may contain `[A-Za-z0-9_]`. The resulting where clause will be formed by replacing each token with the matching key in the parameters map. The value is not transformed in any way, so it must be the appropriate type for the property it is filtering by. If a key is not present in the `Map`, an exception will be thrown. Extra keys will be ignored.

A raw `Predicate` like this one suffers from a few issues. First, predicates are *database specific* that is, after the values from the `parameters` are added to the `format` string, the resulting `String` is evaluated as-is by the underlying database. Perhaps more importantly, there is nothing to verify that the `Predicate` refers to the appropriate column names or that the data in the `parameters` is the right type. This can cause chaos when refactoring code, where a simple name change to a property would break a query. This option is primarily intended to be used as a fallback if `Query<T>.matchOn`is incapable of expressing the desired SQL.

The `matchOn` property of a `Query<T>` is a much safer and elegant way to built a query. The `matchOn` property allows you to assign *matchers* to the properties a `ManagedObject<T>`. A `MatcherExpression` applies a condition - like equal to or less than - to the property it is assigned to. (This follows the same Hamcrest matcher style that the Dart test framework uses.)

The `matchOn` property of a `Query<T>` has the same properties as the managed object being fetched. For each property of `matchOn` that is assigned a matcher, the resulting condition will be built into a generated `Predicate`. Here's an example of a query that finds a `User` with an `id` equal to 1:

```dart
var query = new Query<User>()
  ..matchOn.id = whereEqualTo(1);
```

(The generated SQL here would be 'SELECT \_user.id, \_user.name, ... FROM \_user WHERE \_user.id = 1'.)

All `MatcherExpression`s are created using one of the `where` top-level methods in Aqueduct. Other examples are `whereGreaterThan`, `whereBetween`, and `whereIn`. Every matcher set on a `matchOn` is combined using logical 'and'. In other words, the following query will find all users whose `name` is "Bob" *and* `email` is not null:

```dart
var query = new Query<User>()
  ..matchOn.id = whereEqualTo("Bob")
  ..matchOn.email = whereNotNull;
```

Matcher methods all have a `dynamic` return type, the actual object type is opaque. The `matchOn` property it actually an instance of `ManagedObject<T>`, just like other managed objects you may use in your application. However, it has a special `backingMap` with different behavior than a managed object used to represent a database row.

Relationship properties may also be matched, but there are important nuances to understand. When matching on `ManagedRelationship` properties - the properties that represent foreign key columns - you must use the `whereRelatedByValue` matcher. For example, the following `Query<T>` would fetch all tasks that belong to `User` with `id` equal to 1:

```dart
Do:

var query = new Query<Task>()
  ..matchOn.user = whereRelatedByValue(1);

Do not:
var query = new Query<Task>()
  ..matchOn.user.id = whereEqualTo(1);
```

The `whereRelatedByValue` matcher will determine the primary key of the user managed object to build the predicate. (That is, in this example, the generated SQL is 'SELECT \_task.id, \_task.user_id, ... FROM \_task where \_task.\_user_id = 1'.)

This matcher is only available for `ManagedRelation` properties - the other side of the relationship cannot be fetched in this way. That is covered in the next section.

Setting the `predicate` and using `matchOn` property of a `Query<T>` at the same time has undefined behavior, you should only use one or the other. The `Predicate` generated by a `matchOn` property is database-agnostic.

### Including Relationships in a Fetch (aka, Joins)

A `Query<T>` can fetch objects that include instances of their has-many or has-one relationships alongside their attributes. This allows queries to fetch entire model graphs and reduces the number of round-trip queries to a database. (This type of fetch will execute a SQL LEFT OUTER JOIN.)

To include related objects, you set the `includeInResultSet` to `true` on relationship properties in `Query<T>.matchOn`. The returned managed objects will be the type determined by the `Query<T>` type with values for each of the fetched relationship properties.

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @managedPrimaryKey int id;

  ManagedSet<Task> tasks;
  ...
}

class Task extends ManagedObject<_Task> implements _Task {}
class _Task {
  @managedPrimaryKey int id;

  @ManagedColumnAttributes(#tasks)
  User user;
  ...
}

var q = new Query<User>()
  ..matchOn.id = whereEqualTo(2)
  ..matchOn.tasks.includeInResultSet = true;

var user = await q.fetchOne();

user.id == 2;
user.tasks.every((Task t) =>
  t.id is int &&
  t.user.id == 2 &&
  t.text is String
) == true;
```

As shown, you may still apply matchers to the query. You may also apply matchers to the relationship property. In the case of has-one relationships, this doesn't make much sense - once you've included the only possible related object, filtering doesn't do anything useful. Thus, when fetching has-one properties, you need only set the relationships `includeInResultSet` property.

However, in the case of has-many, it often makes sense to further filter the result set - e.g. fetching a user and their pending tasks, instead of a user and all their entire task history. `ManagedSet`s - the type of has-many relationship properties - *also* have a `matchOn` property to filter which managed objects are returned.

```dart
var q = new Query<User>()
  ..matchOn.id = whereEqualTo(2)
  ..matchOn.tasks.includeInResultSet = true
  ..matchOn.tasks.matchOn.status = whereIn([Status.Pending, Status.RecentlyCompleted]);

var user = await q.fetchOne();

user.id == 2;
user.tasks.every((Task t) =>
  t.id == 1 &&
  t.user.id == 2 &&
  (t.status == Status.Pending || t.status == Status.RecentlyCompleted)
) == true;  
```

There are two important things to note here. First, if `includeInResultSet` is false (the default value), the nested `matchOn` will have no impact on the query (and no instances will be returned for the relationship; adding a matcher does not change this property's behavior).

Second, it is important to understand how nested matchers impact the objects returned. In this previous example, the entity of the `Query<T>` - `User` - has been filtered to only include one user with `id` equal to `2`. Thus, the matcher on `tasks` will only be applied to the tasks for to that user. If the `Users`' `id` matcher expression was removed, every single user and every single one of their tasks that meets the condition would be fetched. This operation, depending on how many users your application had, could be a very expensive query for the underlying database:

```dart
var q = new Query<User>()
  ..matchOn.tasks.includeInResultSet = true
  ..matchOn.tasks.matchOn.status = whereIn([Status.Pending, Status.RecentlyCompleted]);

var usersAndTheirTasks = await q.fetch(); // Probably slow.
```

You may fetch multiple relationship properties on the same managed object, and you may fetch nested relationship properties as well. This is perfectly valid:

```dart
var q = new Query<User>()
  ..matchOn.id = whereEqualTo(2)
  ..matchOn.notes.includeInResultSet = true
  ..matchOn.tasks.includeInResultSet = true
  ..matchOn.tasks.matchOn.status = whereIn([Status.Pending, Status.RecentlyCompleted])
  ..matchOn.tasks.matchOn.locations.includeInResultSet = true;
```

This query would return a single `User` instance, for which it would have notes and tasks, and every task would have locations. Each of these could have additional matchers to further filter the result set. Also note that in this example, the `locations` of `tasks` would already be filtered to only refer to tasks that were `Status.Pending` or `Status.RecentlyCompleted` *and* belong to user with `id` equal to `2`.

While `ManagedRelationship` properties cannot be included using `includeInResultSet`, the functionality is possible by changing the type the `Query<T>` fetches to the related object type.

```dart
// DO NOT includeInResultSet for RelationshipInverse properties:
var q = new Query<Task>()
  ..matchOn.user = whereRelatedByValue(1)
  ..matchOn.user.includeInResultSet = true;

var tasks = await q.fetch(); // This will not include any information about the user other than its id.

// DO go a level higher in the entity hierarchy and filter by the primary key
var q = new Query<User>()
  ..matchOn.id = 1
  ..matchOn.tasks.includeInResultSet = true;

var tasks = await q.fetchOne(); // This will return a user and all tasks in the tasks property.
```

By default, the `defaultProperties` of the included nested relationship objects are fetched. You may set the fetched properties for the instances fetched in a relationship property with `Query<T>.nestedResultProperties`. This `Map<Type, List<String>>`'s values indicate the properties to fetch for the `Type` key. The following example will fetch `id` and `text` when a `Task` is fetched.

```dart
var q = new Query<User>()
  ..nestedResultProperties[Task] = ["id", "text"]
  ..matchOn.id = 1
  ..matchOn.tasks.includeInResultSet = true;
```

Note that a query will always fetch the primary key of a nested object, even if it is omitted in `nestedResultProperties`. (It will not automatically add the foreign key used to join the related object.)

### Exceptions and Errors

An error encountered in preparing or executing a query will throw a `QueryException`. `PersistentStore` subclasses generate instances of `QueryException` and specify the type of event that caused the exception - a value in `QueryExceptionEvent`.

`RequestController`s, by default, will interpret the event of a `QueryException` to return a `Response` to an HTTP client. For common scenarios - like a unique violation generating an exception with suggested status code of `409` - Aqueduct will return a reasonable status code to the requesting HTTP client. Therefore, you do not have to catch query executions unless you wish to override the returned status code.

### Statement Reuse

Aqueduct will parameterize and reuse queries when possible. This allows for significant speed and security improvements. Note that you do not have to do anything special to take advantage of this feature. However, currently at this time, you may not disable this feature.
