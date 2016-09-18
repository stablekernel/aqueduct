## `Query` Instances Send Commands to a Database

To send commands to a database - whether to fetch, insert, delete or update objects - you will create, configure and execute instances of `Query`. A `Query` allows you to create database operations in Dart code in the domain of your application, as opposed to writing SQL. `Query`s are executed against a `ModelContext`. By default, every `Query` uses `ModelContext.defaultContext`, but this can be changed during the instantiation of a `Query`.

(Note that raw SQL may be sent to a database in an Aqueduct application using instances of `PersistentStore` directly. Queries are meant for data operations, not database management.)

Instances of `Query` are generic. The type parameter indicates the entity you are fetching, inserting, deleting or updating. The type parameter must be a subclass of `Model` for which a fully formed `ModelEntity` exists. When a `Query` is created, it sets its `entity` property to `ModelEntity` that represents its type parameter:

```dart
var query = new Query<User>();

query.entity.instanceType; // -> ClassMirror on 'User'
```

The `DataModel` that a `Query`'s `entity` must belongs to same `ModelContext` as the `Query`'s `context`.

A `Query` has four basic execution methods: `fetch`, `update`, `insert`, `delete`. These methods will perform a database operation based on the information configured in the `Query`.

* `fetch` will retrieve data from a database (it is equivalent to the SQL operation `SELECT`). Rows are returned in instances of the `Query`'s generic type.
* `update` will modify existing data in a database (it is equivalent to the SQL operation `UPDATE`). Rows are returned in instances of the `Query`'s generic type.
* `insert` will add new data to a database (it is equivalent to the SQL operation `INSERT`). Rows are returned in instances of the `Query`'s generic type.
* `delete` will remove data from a database (it is equivalent to the SQL operation `DELETE`). The number of rows deleted is returned as an integer.

A `Query` has properties that dictate the information that will be used in their execution methods. These properties will impact which objects get fetched, the data that gets sent to the database, the order that data is returned in, and so on. A `Query` is not instantiated with a pre-determined execution method; the same `Query` can be used to `fetch` objects and then used to `delete` objects without any changes. The `Query` does not maintain any state about execution methods executed or results from an execution of it.

### Inserting Data with a Query

To configure a query to insert an object into a database, you must first create an instance of `Query`. The type argument must be the instance type of the entity you are inserting. To specify the values to insert, every `Query` has a `values` properties. Setting values in this instance configures the values the `Query` will insert when it is executed. For example, if there was a `User` entity with a `name` and `email`, you would configure a `Query` to insert an instance of `User` like so:

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  
```

The `values` property of a `Query` will automatically be created as soon as you access it. You may also provide an instance to `values` directly; this comes in handy when you are getting an object from an HTTP request body:

```dart
var user = new User()
  ..readMap(requestBody);

var query = new Query<User>()
  ..values = user;
```

(You may optionally configure a `Query`'s `valueMap` to supply values for an insert query, but this is less desirable because `valueMap` is stringly-typed whereas `values` is both key-checked and type-checked. You may only use one or the other. If both `valueMap` and `values` are configured, the `Query`'s behavior is undefined.)

Once a `Query` has been configured with values, it may be executed as an insert command. The value returned from an insert will be the newly inserted instance inside a `Future`.

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  

User user = await query.insert();
user.name; // "Bob"
user.email; // "bob@stablekernel.com"
user.id; // 1
```

Since most model objects have an auto-incrementing primary key, it is important to get the returned model object from an insert execution, as it will contain the generated primary key value.

Note that only the data explicitly set in `values` (or `valueMap`) is sent to the database. Unset values are *not* sent as `null` and entirely omitted from the insert command.

If an insert query fails because of a conflict - a unique constraint is violated - Aqueduct will automatically generate an `HTTPResponseException` with a 409 status code. This default behavior means that you don't have to check for the specific error of unique constraint violation and Aqueduct will abandon execution and return a 409 'Conflict' response to the calling client.

### Updating Data with a Query

Updating data with a `Query` is similar to inserting data in that the data you set the `values` of a `Query` for data you want to change. The type parameter for the `Query` indicates which entity - and therefore which database table - will get updated when the query is executed.

An update query can - and likely should be - restricted to a single row or multiple rows. This is done by using the `matchOn` or `predicate` property of a `Query` - which gets translated into the *where clause* of the underlying SQL statement.

Because a `Query`s `predicate` and `matchOn` properties can be used for update, fetch and delete queries, and they are such a large topic, there is a separate section reserved specifically for those properties. For the purpose of understanding update queries, know that the `matchOn` and `predicate` properties allow you to identify specific rows in a database.

By executing an update query, the specified rows will get new values for all of the values in `values` (or `valueMap`). Only the `values` explicitly specified in the query will be modified by the update query. In effect, this means you do not have to fetch an object before updating it - you can provide only the values you wish to update and the remainder of the row is unmodified.

```dart
// A Query that will change any user's whose name is 'Bob' to 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..matchOn.name = whereEqualTo("Bob");

List<User> bobsThatAreNowFreds = await query.update();
```

An update query modifies rows in the database and returns every modified row as a result. Only rows that were updated will be returned and they will be returned as instances of the appropriate `Model` subclass. There is a variant to `Query`'s `update` method named `updateOne`. The `updateOne` method will build and execute a SQL query in the same way a normal `update` does, however, it will return you a single instance that was updated instead of a list. This is convenience method for the caller to get back a single instance instead of a list:

```dart
// Update user with id = 1 to have the name 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..matchOn.id = whereEqualTo(1);

User updatedUser = await query.updateOne();
```

The `updateOne` method will return `null` if no rows were updated. It is important to note that if `updateOne` is used and more than one row is updated, `updateOne` will throw an exception and the changes to the data *are not reversible*. Because this is likely a mistake, this is considered an error, hence the exception is thrown. It is up to the programmer to recognize whether or not a particular `updateOne` query would impact multiple rows.

If an update violates a unique property, an `HTTPResponseException` with status code 409 will be thrown.

Update queries have a safety feature that prevents you from accidentally updating every row. If you try to execute a `Query` to do an update and no `predicate` or `matchOn` property is defined, the default behavior of `Query` will throw an exception prior to carrying out the request. If you explicitly want to update every instance of some entity (that is, every row of a table), you must set the `Query`'s `confirmQueryModifiesAllInstancesOnDeleteOrUpdate` to `true` prior to execution. (This property defaults to `false`.)

### Deleting Data with a Query

A delete `Query` will delete rows from a database for the entity specified by its type argument. Like update and fetch queries, you may specify a row or rows using `matchOn` and `predicate` properties of the `Query`. The result of a delete operation will be a `Future` with the number of rows deleted.

```dart
var query = new Query<User>()
  ..matchOn.id = 1;

int usersDeleted = await query.delete();
```

Also like update queries, delete queries have a safety feature that prevents you from accidentally deleting every row in a table. If you try to execute a `Query` to do an update and no `predicate` or `matchOn` property is defined, the default behavior of `Query` will throw an exception prior to carrying out the request. If you explicitly want to delete every instance of some entity (that is, every row of a table), you must set the `Query`'s `confirmQueryModifiesAllInstancesOnDeleteOrUpdate` to `true` prior to execution.

Any properties set in the query's `values` or `valueMap` are ignored when executing a delete.


### Fetching Data with a Query

Of the four basic operations of a `Query`, fetching data is the most configurable and powerful. In its simplest form, a fetch query will return matching instances for an entity (that is, matching rows from a table). A simple `Query` that would fetch every instance of some entity looks like this:

```dart
var query = new Query<User>();

List<User> allUsers = await query.fetch();
```

A fetch `Query` uses its `matchOn` and `predicate` to filter the result set, just like delete and update queries. Any properties set in the query's `values` or `valueMap` are ignored when executing a fetch. In addition to fetching a list of instances from a database, you may also fetch a single instance with `fetchOne`. If no instance is found, `null` is returned. (If more than one instance is found, an exception is thrown.)

```dart
var query = new Query<User>()
  ..matchOn.id = 1;

User oneUser = await query.fetchOne();
```

Fetches can be limited to a number of instances by setting the `fetchLimit` property of a `Query`. You may also set the `offset` of a `Query` to skip the first `offset` number of rows. Between `fetchLimit` and `offset`, you can implement naive paging. However, this type of paging suffers from a number of problems and so there is a built-in paging mechanism covered in a later section.

Results of a fetch can be sorted by adding `SortDescriptor`s to a `Query`'s `sortDescriptors` property. A `SortDescriptor` has a key (the name of a property on a entity) and the order in which rows should be sorted (ascending or descending). For example, the following would return users in alphabetical order based on their name, from A-Z:

```dart
var query = new Query<User>()
  ..sortDescriptors = [new SortDescriptor("name", SortDescriptorOrder.ascending)];

List<User> orderedUsers = await query.fetch();
```

A `Query` can have multiple sort descriptors. Subsequent sort descriptors are used to break ties in previous sort descriptors. The order sort descriptors are applied in is the order they are listed in the `sortDescriptors` list.

Fetch queries can fetch an entity's relationships (these are carried out as *database joins* by the `PersistentStore`). Because this is a more complex topic, this discussion is reserved for a later section.

### Specifying Result Properties

When executing a query that returns model objects (i.e., insert, update and fetch queries), you may configure which properties are actually fetched for each instance. Every entity has a set of `defaultProperties`. If you do not specify exactly which properties to be fetched, these an instance will have all of the properties in its entity's `defaultProperties` set in its `backingMap`.

The default properties of an entity are all attributes declared in the persistent type that do not explicitly have the `omitByDefault` `AttributeHint` set to true and all `InverseRelationship` properties. (In other words, every actual column on the corresponding database table that you haven't specifically marked to be ignored.)

Properties like a hashed password and salt are likely candidates to be marked as `omitByDefault`, as you don't typically want to return that information in an HTTP response body. Marking a attribute as such frees you from having to exclude it each time you create a `Query`.

If you wish to specify which properties are fetched into an instance when performing a `Query`, you may set the `Query`'s `resultProperties`. This `List<String>` is the name of each property you wish to be fetched. This list is the exact set of properties to be fetched - it does not also include properties from an entity's `defaultProperties`. This property is useful when you want to limit the properties fetched from a query. (Bear in mind, an un-fetched property will be omitted from the `Map` as a result of serialized model object.) Additionally, setting the `resultProperties` of a `Query` is the only way to fetch properties that are marked as `omitByDefault`.

```dart
class User extends Model<_User> implements _User {}
class _User {
  @primaryKey int id;

  String name;
  String gender;

  @AttributeHint(unique: true, indexed: true)
  String email;

  @AttributeHint(omitByDefault: true)
  String hashedPassword;

  @AttributeHint(omitByDefault: true)
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

If you specify a property that doesn't exist for an entity in `resultProperties`, you will get an exception when the `Query` is executed.

You may not add a 'hasMany' or 'hasOne' relationship to `resultProperties`, as this mechanism is achieved by other functionality on a `Query`. If you do add a 'hasOne' or 'hasMany' relationship property name to the list of `resultProperties`, an exception will be thrown when the query is executed.

### Paging Fetched Result Sets

In larger data sets, it may make sense to only return a portion of rows from a database. For example, in a social media application, a user could have thousands of pieces of content they had created over many years. The likely use case for fetching their content would be to grab only the most recent content, and only grab earlier content as necessary. There are many ways to accomplish paging, and the right solution oftentimes depends on the context and may require additional services beyond just a single database - Aqueduct doesn't pretend to fully solve this problem. Aqueduct does provide two mechanisms on `Query` instances for building queries that can fetch a subset of rows within a certain range.

First, naive paging can be accomplished using the `fetchLimit` and `offset` properties of a `Query`. For example, if a table contains 100 rows, and you would like to vend them out 10 at a time to a client, each query would have a value of 10 for its `fetchLimit`. The first query would have an `offset` of 0, then 10, then 20, and so on. Especially when adding `sortDescriptors` to a `Query`, this type of paging can be effective.

One of the drawbacks to this type of paging is that it can skip or duplicate rows if rows are being added or deleted while fetching subsequent pages. For example, if a table again contains 100 rows, and you have made two queries to fetch the first 20, the next query (to grab rows 20-29) should have an `offset` of 20 and a `fetchLimit` of 10. If a row is inserted prior to executing the third query that gets rows 20-29, the row that was previously #19 gets moved into the #20 slot. Thus, the query to get rows 20-29 will contain a duplicate from the previous query. Likewise, if a row is deleted from within the first 20 rows, what would have been row #20 moves into slot #19. When fetching rows 20-29, #19 is not fetched and it is skipped.

Therefore, `Query` has a property named `pageDescriptor` (an instance of `QueryPage`) to better handle paging and avoid the problem of sliding rows. A `QueryPage` specifies which property of the entity defines row order, a value for that property that indicates the point where the query starts fetching rows from, and a direction to fetch the rows in.

For example, consider an entity that has a `createdDate` property:

```dart
class Task extends Model<_Task> implements _Task {}
class _Task {
  @primaryKey int id;
  String text;

  @AttributeHint(indexed: true)
  DateTime createdDate;
}
```

In an application that displays a timeline of `Task`s, a user would most likely want to see their most recent five tasks first. Then, if they choose to continue browsing, the next five tasks after that, and then the next five and so on. Thus, the property a `QueryPage` refers to is the `createdDate`.

This timeline query should fetch rows such that the first row is the newest and the next row is less recent. Since most recent dates are *greater than*


A `QueryPage` has a `propertyName` value that indicates which property of the entity should be used to determine order. In this example, `createdDate` would be as the order-determining property of a timeline.

The `referenceValue` of a `QueryPage` determines the beginning of the page to be fetched. This value must be a valid value for the order-determining property of the page. In this example, `referenceValue` must be a `DateTime` since `createdDate` is a `DateTime`. Finally, `QueryPage`'s


***
Failures, exceptions
nestedResultProperties
Joins
Offset/fetch limit
Sort descriptors
paging
Statement reuse
