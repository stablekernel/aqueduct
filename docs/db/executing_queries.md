# Inserting, Updating, Deleting and Fetching Objects

To send commands to a database - whether to fetch, insert, delete or update objects - you will create, configure and execute instances of `Query<T>`. The type argument must be a subclass of `ManagedObject<T>`. This tells the `Query<T>` which table it will operate on. Here's an example of a `Query<T>` that fetches all instances of `User`:

```dart
var query = new Query<User>();
var allUsers = await query.fetch();
```

A `Query<T>` has four basic execution methods: `fetch`, `update`, `insert`, `delete`.

* `fetch` will retrieve data from a database (it is equivalent to the SQL operation `SELECT`).
* `update` will modify existing data in a database (it is equivalent to the SQL operation `UPDATE`).
* `insert` will add new data to a database (it is equivalent to the SQL operation `INSERT`).
* `delete` will remove data from a database (it is equivalent to the SQL operation `DELETE`).

A `Query<T>` has many configurable properties. These properties will impact which objects get fetched, the data that gets sent to the database, the order that data is returned in, and so on.

### Inserting Data with a Query

Let's assume there exists a managed object type declared like this:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @managedPrimaryKey
  int id;

  @ManagedColumnAttributes(indexed: true)
  String email;

  String name;
}
```

To insert a new row into the `_User` table, a `Query<T>` is constructed and executed like so:

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  

var user = await query.insert();  
user.asMap() == {
  "id": 1,
  "name": "Bob",
  "email": "bob@stablekernel.com"
};
```

Every `Query<T>` has a `values` property that is the type of managed object being inserted. Here, `values` is an instance of `User`. When a `Query<T>` is executed with insert, a new row is created in the database with every property that has been set for `values`. In this case, both `name` and `email` have been set. The generated SQL looks like this:

```sql
INSERT INTO _user (name, email) VALUES ('Bob', 'bob@stablekernel.com')
```

Note there is no value provided for the `id` property in this query. Recall that `managedPrimaryKey` metadata is a convenience for `ManagedColumnAttributes` with `autoincrementing` behavior. Therefore, the database will assign a value for `id` during insertion. The object returned from `insert()` will be an instance of `User` that represents the inserted row. Thus, the returned `User` will have all of the values that were set in `Query<T>.values` as well as the auto-generated `id` value.

Properties that are not set in the `values` property will not be sent to the database. Values that are explicitly set to `null` will be sent as `NULL`. For example, consider the following `Query<T>`:

```dart
var query = new Query<User>()
  ..values.name = null;
await query.insert();
```

The generated SQL for this query does not send `email` - because it isn't included - and sends `NULL` for `name`:

```sql
INSERT INTO _user (name) VALUES (NULL);
```

If a property is not nullable (its `ManagedColumnAttributes` has `nullable: false`) and its value is not set in a query prior to inserting it, the query will fail and throw an exception.

You may also set `values` with an instance of a managed object. This is valuable when reading an object from a JSON HTTP request body:

```dart
var user = new User()
  ..readMap(requestBody);

var query = new Query<User>()
  ..values = user;
```

By default, the returned object from an `insert()` will have all of its properties set. See a later section on configuring which properties are returned from a `Query<T>`.

If an insert query fails because of a conflict - a unique constraint is violated - the `Query<T>` will throw a `QueryException`.  See a later section on how `QueryException`s are gracefully handled by `RequestController`s. In short, it is unlikely that you have to handle `QueryException` directly - `RequestController`s know how to turn them into the appropriate HTTP response.

### Updating Data with a Query

Updating rows with a `Query<T>` is similar to inserting data, in that you set the `values` of a `Query<T>` for data you want to change. The type parameter for the `Query<T>` indicates which entity - and therefore which database table - will get updated when the query is executed.

An update query can - and likely should - be restricted to a single row or subset of rows. This is done by configuring the `where` property of a `Query<T>` - which gets translated into the *where clause* of the SQL command. Here's an example:

```dart
// A Query that will change any user's whose name is 'Bob' to 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..where.name = whereEqualTo("Bob");

List<User> bobsThatAreNowFreds = await query.update();
```

Like `values`, `where` is also the same managed object type the query is being executed on. In the above example, then, both `values` and `where` and instances of `User`. This query executes the following SQL:

```sql
UPDATE _user SET name='Fred' WHERE name='Bob';
```

The `where` property is a very powerful and flexible, and so there is an entire section dedicated to it later in this guide. For now, we'll stick to some of the things specific to `update()`.

Like `insert()`, only the values set in the `values` property of a query get updated when executing `update()`. Values that are omitted are not included. Values that need to be set to `null` must explicitly be set to `null` in the query:

```dart
// A Query that will remove names from anyone currently named Bob.
var query = new Query<User>()
  ..values.name = null
  ..where.name = whereEqualTo("Bob");
```


An update query returns every modified row as a result. If no rows are updated, the return value is an empty list.  

There is a variant to `Query<T>.update` named `updateOne`. The `updateOne` method will build and execute a SQL query in the same way a normal `update` does, however, it will only return the single instance that was updated instead of a list. This is convenience method for the caller to get back a single instance instead of a list:

```dart
// Update user with id = 1 to have the name 'Fred'
var query = new Query<User>()
  ..values.name = "Fred"
  ..matchOn.id = whereEqualTo(1);

var updatedUser = await query.updateOne();
```

The `updateOne` method will return `null` if no rows were updated. It is important to note that if `updateOne` is used and more than one row is updated, `updateOne` will throw an exception and the changes to the data *are not reversible*. Because this is likely a mistake, this is considered an error, hence the exception is thrown. It is up to the programmer to recognize whether or not a particular `updateOne` query would impact multiple rows.

Update queries have a safety feature that prevents you from accidentally updating every row. If you try to execute a `Query<T>` to do an update and no values in `where` have been set, the default behavior of `Query<T>` will throw an exception prior to carrying out the request. If you actually want to update every instance of some entity (that is, every row of a table), you must set the `Query<T>`'s `canModifyAllInstances` to `true` prior to execution. (This property defaults to `false`.)

### Deleting Data with a Query

A `Query<T>` will delete rows from a database when using `delete()`. Like update queries, you should specify a row or rows using `where` properties of the `Query<T>`. The result of a delete operation will be a `Future<int>` with the number of rows deleted.

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo(1);

int usersDeleted = await query.delete();
```

Also like update queries, delete queries have a safety feature that prevents you from accidentally deleting every row in a table with `canModifyAllInstances`.

Any properties set in the query's `values` are ignored when executing a delete.

### Fetching Data with a Query

Of the four basic operations of a `Query<T>`, fetching data is the most configurable. A simple `Query<T>` that would fetch every instance of some entity looks like this:

```dart
var query = new Query<User>();

List<User> allUsers = await query.fetch();
```

A fetch `Query<T>` uses its `where` property to filter the result set, just like delete and update queries. Any properties set in the query's `values` are ignored when executing a fetch, since there is no need for them. In addition to fetching a list of instances from a database, you may also fetch a single instance with `fetchOne`. If no instance is found, `null` is returned. (If more than one instance is found, an exception is thrown.)

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo(1);

User oneUser = await query.fetchOne();
```

Fetch queries can be limited to a number of instances with the `fetchLimit` property. You may also set the `offset` of a `Query<T>` to skip the first `offset` number of rows. Between `fetchLimit` and `offset`, you can implement naive paging. However, this type of paging suffers from a number of problems and so there is another paging mechanism covered in later sections.

Many of the other fantastic things you can do with fetch queries - like joins, sorting and complex predicates - all deserve their own section and are covered later.

### Specifying Result Properties

When executing queries that return managed objects (i.e., `insert()`, `update()` and `fetch()`), the default properties for each object are fetched. The default properties of a managed object are properties that correspond to a database column - attributes declared in the persistent type. A managed object's default properties can be modified when declaring its persistent type:

```dart
class _User {
  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;
}
```

Any property with `omitByDefault` set to true will not be fetched by default.

A property that is `omitByDefault` can still be fetched. Likewise, a property that is in the defaults can still be omitted. Each `Query<T>` has a `returningProperties` method to adjust which properties do get returned from the query. Its usage looks like this:

```dart
var query = new Query<User>()
  ..returningProperties((user) => [user.id, user.name]);
```

The method `returningProperties` takes a closure with one argument - an instance of the type being queried. The closure must return a `List` of properties to be fetched. Here, both `user.id` and `user.name` are returned and this `Query<T>` will fetch a user's `id` and `name` properties only. (The SQL would be something like `SELECT id, name FROM _User`.) Note that the properties returned from this closure *are not* added to the list of default properties - the list is an exact set of properties to be returned.

The way `returningProperties` is constructed is a little interesting. You may look at this code and expect the closure's return value to be something like `[1, "Bob"]` - a `List` with an `id` and a `name`. Instead, `ManagedObject<T>` and `Query<T>` work together to interpret the return value differently. The benefit of this approach is best explained by comparing it to another approach:

```dart
var query = new Query<User>()
  ..returningProperties = ["id", "name"]; // This code is not valid!
```

In the above approach - which is not valid code - the names of the properties are `String`s. The drawback here is that there is no way for the analyzer to tell us if `id` and `name` are actually properties of a `User` or if we misspelled one of the properties. We'd only find out at runtime. Additionally, we get the benefit of code completion and refactoring tools when using the closure approach. Many other features of `Query<T>` like joins, paging and sorting use a similar construct to identify which properties are being used in the query.

If you specify a property that doesn't exist for a managed object in `returningProperties`, you will get an exception when the `Query<T>` is executed.

You may not add a 'has-many' or 'has-one' relationship to `returningProperties`, as this mechanism is achieved by the methods `joinOne` and `joinMany`. If you do add a 'has-one' or 'has-many' relationship property name to the list of `returningProperties`, an exception will be thrown when the query is executed.

Note that if you omit the primary key of a managed object from `returningProperties`, it will automatically be added. The primary key is necessary to transform the rows into instances of their `ManagedObject<T>` subclass.

### Sorting

Results of a fetch can be sorted using the `sortBy` method of a `Query<T>`. Here's an example:

```dart
var q = new Query<User>()
  ..sortBy((u) => u.dateCreated, QuerySortOrder.ascending);
```

`sortBy` takes two arguments: a closure that returns which property to sort by and the order of the sort.

A `Query<T>` results can be sorted by multiple properties. When multiple `sortBy`s are invoked on a `Query<T>`, later `sortBy`s are used to break ties in previous `sortBy`s. For example, the following query will sort by last name, then by first name:

```dart
var q = new Query<User>()
  ..sortBy((u) => u.lastName, QuerySortOrder.ascending)
  ..sortBy((u) => u.firstName, QuerySortOrder.ascending);
```

Thus, the following three names would be ordered like so: 'Sally Smith', 'John Wu', 'Sally Wu'.

### Exceptions and Errors

An error encountered in preparing or executing a query will throw a `QueryException`. `RequestController`s, by default, will interpret the event of a `QueryException` to return a `Response` to an HTTP client. For common scenarios - like a unique violation generating an exception with suggested status code of `409` - Aqueduct will return a reasonable status code to the requesting HTTP client. Therefore, you do not have to catch query exceptions unless you wish to override the suggested status code.

### Statement Reuse

Aqueduct will parameterize and reuse queries when possible. This allows for significant speed and security improvements. Note that you do not have to do anything special to take advantage of this feature. However, currently at this time, you may not disable this feature.
