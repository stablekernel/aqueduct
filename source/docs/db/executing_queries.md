# Inserting, Updating, Deleting and Fetching Objects

To send commands to a database - whether to fetch, insert, delete or update objects - you will create, configure and execute instances of `Query<T>`. The type argument must be a subclass of `ManagedObject`, which determines the table the query will operate on.

A query compiles and executes a SQL query and requires a [ManagedContext](connecting.db) to determine the database to connect to. Here's an example of a `Query<T>` that fetches all instances of `User`:

```dart
final query = Query<User>(context);
final allUsers = await query.fetch();
```

A `Query<T>` has four basic execution methods: `fetch`, `update`, `insert`, `delete`.

* `fetch` will retrieve data from a database (it is equivalent to the SQL operation `SELECT`).
* `update` will modify existing data in a database (it is equivalent to the SQL operation `UPDATE`).
* `insert` will add new data to a database (it is equivalent to the SQL operation `INSERT`).
* `delete` will remove data from a database (it is equivalent to the SQL operation `DELETE`).

A `Query<T>` has many configurable properties. These properties will impact which objects get fetched, the data that gets sent to the database, the order that data is returned in, and so on.

In the following sections, assume that a `User` managed object subclass exists that is declared like so:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  @Column(indexed: true)
  String email;

  String name;
}
```

### Inserting Data with a Query

To insert data with a query, you create a new `Query<T>` object, configure its `values` property and then call its `insert()` method.

```dart
final query = Query<User>(context)
  ..values.name = "Bob"
  ..values.email = "bob@stablekernel.com";  

final user = await query.insert();  
```

The `values` of a `Query<T>` is an instance of `T` (the managed object type you are inserting). You can configure individual properties of `values`, or you can assign `values` to an instance you have created elsewhere:

```dart
final userValues = User()
  ..name = "Bob"
  ..email = "bob@stablekernel.com";
final query = Query<User>(context)..values = userValues;
final user = await query.insert();  
```

Either way, this query is translated into the following SQL:

```sql
INSERT INTO _user (name, email) VALUES ('Bob', 'bob@stablekernel.com') RETURNING id, name, email;
```

Notice that only the values set on the `values` object are included in the SQL INSERT query. In this example, both `name` and `email` were set, but not `id` and therefore only `name` and `email` were included in the query. (In this case, the primary key is auto-incrementing and the database will generate it.)

Values that are explicitly set to `null` will be sent as `NULL`. For example, consider the following `Query<T>` and its SQL:

```dart
var query = Query<User>(context)
  ..values.name = null
  ..email = "bob@stablekernel.com";

// INSERT INTO _user (name, email) VALUES (NULL, 'bob@stablekernel.com') RETURNING id, name, email;
await query.insert();
```

An insert query will return a managed object that represents the row that is inserted.

!!! warning "Prefer the Inserted Object"
    After you insert an object, you should prefer to use the object returned by an insert query rather than the values you used to populate the query. The object returned from the query will be an accurate representation of the database row, while the object used to build the query may be incomplete or different. For example, an auto-incrementing primary key won't be available in your query-building instance, but will in the object returned from the successful query.

There is one difference to note when choosing between assigning an instance to `values`, or configuring the properties of `values`. In an instance you create, a relationship property must be instantiated before accessing its properties. When accessing the relationship properties of `values`, an empty instance of the related object is created immediately upon access.

```dart
final employee = Employee()
  ..manager.id = 1; // this is a null pointer exception because manager is null

final query = Query<Employee>(context)
  ..values.manager.id = 1; // this is OK because of special behavior of Query
```

Once you assign an object to `values`, it will adopt the behavior of `values` and instantiate relationships when accessed. Also note that after assigning an object to `values`, changes to the original object are not reflected in `values`. In other words, the object is copied instead of referenced.

For simple insertions and for inserting more than one object, you can use the methods on the context:

```dart
final context = ManagedContext(...);
final bob = User()..name = "Bob";
final jay = User()..name = "Jay";

final insertedObject = await context.insertObject(bob);
final insertedObjects = await context.insertObjects([bob, jay]);
```

### Updating Data with a Query

Updating rows with a `Query<T>` is similar to inserting data: you set the `Query.values` for properties you want to change. The type parameter for the `Query<T>` indicates which database table will get updated when the query is executed.

An update query can - and likely should - be restricted to a single row or subset of rows. This is done by configuring the `Query.where` property - which gets translated into the *where clause* of the SQL command. Here's an example:

```dart
// A Query that will change any user's whose name is 'Bob' to 'Fred'
var query = Query<User>(context)
  ..values.name = "Fred"
  ..where((u) => u.name).equalTo("Bob");

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
var query = Query<User>(context)
  ..values.name = null
  ..where((u) => u.name).equalTo("Bob");
```


An update query returns every modified row as a result. If no rows are updated, the return value is an empty list.  

There is a variant to `Query<T>.update` named `updateOne`. The `updateOne` method will build and execute a SQL query in the same way a normal `update` does, however, it will only return the single instance that was updated instead of a list. This is convenience method for the caller to get back a single instance instead of a list:

```dart
// Update user with id = 1 to have the name 'Fred'
var query = Query<User>(context)
  ..values.name = "Fred"
  ..where((u) => u.id).equalTo(1);

var updatedUser = await query.updateOne();
```

The `updateOne` method will return `null` if no rows were updated. It is important to note that if `updateOne` is used and more than one row is updated, `updateOne` will throw an exception and the changes to the data *are not reversible*. Because this is likely a mistake, this is considered an error, hence the exception is thrown. It is up to the programmer to recognize whether or not a particular `updateOne` query would impact multiple rows.

Update queries have a safety feature that prevents you from accidentally updating every row. If you try to execute a `Query<T>` to do an update without configuring `where`, an exception is thrown prior to carrying out the request. If you actually want to update every row of a table, you must set the `Query.canModifyAllInstances` to `true` prior to execution. (This property defaults to `false`.)

### Deleting Data with a Query

A `Query<T>` will delete rows from a database when using `delete()`. Like update queries, you should specify a row or rows using `where` properties of the `Query<T>`. The result of a delete operation will be a `Future<int>` with the number of rows deleted.

```dart
var query = Query<User>(context)
  ..where((u) => u.id).equalTo(1);

int usersDeleted = await query.delete();
```

Also like update queries, delete queries have a safety feature that prevents you from accidentally deleting every row in a table with `canModifyAllInstances`.

Any properties set in the query's `values` are ignored when executing a delete.

### Fetching Data with a Query

Of the four basic operations of a `Query<T>`, fetching data is the most configurable. A simple `Query<T>` that would fetch every instance of some entity looks like this:

```dart
var query = Query<User>(context);

List<User> allUsers = await query.fetch();
```

Fetch queries can be limited to a number of instances with the `fetchLimit` property. You may also set the `offset` of a `Query<T>` to skip the first `offset` number of rows. Between `fetchLimit` and `offset`, you can implement naive paging. However, this type of paging suffers from a number of problems and so there is another paging mechanism covered in later sections.

A fetch `Query<T>` uses its `where` property to filter the result set, just like delete and update queries. The `values` of a query are ignored when fetching objects. You may also fetch a single instance with `fetchOne`. If no instance is found, `null` is returned. Only use this method when the search criteria is guaranteed to be unique.

```dart
var query = Query<User>(context)
  ..where((u) => u.id).equalTo(1);

User oneUser = await query.fetchOne();
```

When you are fetching an object by its primary key, you can use a shorthand method `ManagedContext.fetchObjectWithID`. The method must be able to infer the type of the object, or you must provide it:

```dart
final object = await context.fetchObjectWithID<User>(1);
```

### Sorting

Results of a fetch can be sorted using the `sortBy` method of a `Query<T>`. Here's an example:

```dart
var q = Query<User>(context)
  ..sortBy((u) => u.dateCreated, QuerySortOrder.ascending);
```

`sortBy` takes two arguments: a closure that returns which property to sort by and the order of the sort.

A `Query<T>` results can be sorted by multiple properties. When multiple `sortBy`s are invoked on a `Query<T>`, later `sortBy`s are used to break ties in previous `sortBy`s. For example, the following query will sort by last name, then by first name:

```dart
var q = Query<User>(context)
  ..sortBy((u) => u.lastName, QuerySortOrder.ascending)
  ..sortBy((u) => u.firstName, QuerySortOrder.ascending);
```

Thus, the following three names would be ordered like so: 'Sally Smith', 'John Wu', 'Sally Wu'.

### Property Selectors

In the section on sorting, you saw the use of a *property selector* to select the property of the user to sort by. This syntax is used for many other query manipulations, like filtering and joining. A property selector is a closure that gives you an object of the type you are querying and must return a property of that object. The selector `(u) => u.lastName` in the previous section is a property selector that selects the last name of a user.

The Dart analyzer will infer that the argument of a property selector, and it is always the same type as the object being queried. This enables IDE auto-completion, static error checking, and other tools like project-wide renaming.

!!! tip "Live Templates"
    To speed up query building, create a Live Template in IntelliJ that generates a property selector when typing 'ps'. The source of the template is `(o) => o.$END$`. A downloadable settings configuration for IntelliJ exists [here](../intellij.md) that includes this shortcut.


## Specifying Result Properties

When executing queries that return managed objects (i.e., `insert()`, `update()` and `fetch()`), the default properties for each object are fetched. The default properties of a managed object are properties that correspond to a database column - attributes declared in the table definition. A managed object's default properties can be modified when declaring its table definition:

```dart
class _User {
  @Column(omitByDefault: true)
  String hashedPassword;
}
```

Any property with `omitByDefault` set to true will not be fetched by default.

A property that is `omitByDefault` can still be fetched. Likewise, a property that is in the defaults can still be omitted. Each `Query<T>` has a `returningProperties` method to adjust which properties do get returned from the query. Its usage looks like this:

```dart
var query = Query<User>(context)
  ..returningProperties((user) => [user.id, user.name]);
```

`returningProperties` is a multiple property selector - instead of returning just one property, it returns a list of properties.

You may include 'belongs-to' relationships in `returningProperties`, but you may not include 'has-many' or 'has-one' relationships. An exception will be thrown if you attempt to. To include properties from relationships like these, see [join in Advanced Queries](advanced_queries.md).

Note that if you omit the primary key of a managed object from `returningProperties`, it will automatically be added. The primary key is necessary to transform the rows into instances of their `ManagedObject<T>` subclass.

### Exceptions and Errors

When executing a query, it may fail for any number of reasons: the query is invalid, a database couldn't be reached, constraints were violated, etc. In many cases, this exception originates from the underlying database driver. When thrown in a controller, these exceptions will trigger a 500 Server Error response.

Exceptions that are thrown in response to user input (e.g., violating a database constraint, invalid data type) are re-interpreted into a `QueryException` or `ValidationException`. Both of these exception types have an associated `Response` object that is sent instead of the default 500 Server error.

For this reason, you don't need to catch database query exceptions in a controller; an appropriate response will be sent on your behalf.

### Statement Reuse

Aqueduct will parameterize and reuse queries when possible. This allows for significant speed and security improvements. Note that you do not have to do anything special to take advantage of this feature. However, currently at this time, you may not disable this feature.
