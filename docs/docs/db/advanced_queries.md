# Advanced Queries: Filtering, Joins and Paging



### Paging Fetched Result Sets

In larger data sets, it may make sense to only return a portion of rows from a database. For example, in a social media application, a user could have thousands of pieces of content they had created over many years. The likely use case for fetching their content would be to grab only the most recent content, and only grab earlier content as necessary. Aqueduct has two mechanisms in `Query<T>` for building queries that can fetch a subset of rows within a certain range.

Naive paging can be accomplished using the `fetchLimit` and `offset` properties of a `Query<T>`. For example, if a table contains 100 rows, and you would like to grab 10 at a time, each query would have a value of 10 for its `fetchLimit`. The first query would have an `offset` of 0, then 10, then 20, and so on. Especially when using `sortBy`, this type of paging can be effective. One of the drawbacks to this type of paging is that it can skip or duplicate rows if rows are being added or deleted between fetches.

For example, a table contains 100 rows and you're fetching ten at a time. After two queries, you've fetched 20 total. The next query will fetch rows 21-30 - but before that, a new row is inserted at row 10. That means the old row 10 moves to row 11, row 11 moves to row 12 and so on. Most importantly, row 20 moves to row 21; and the next query will fetch row 21. This row was already fetched in the previous query, so it shows up as a duplicate. (Yes, this needs a diagram.)

A similar issue occurs if a row is deleted from within the first 20 rows after they have been fetched. Row 21 slides down to row 20, so the next query won't fetch that row.

A `Query<T>` has a method named `pageBy` to better handle paging and avoid the problem of sliding rows. The usage of `pageBy` is similar to `sortBy`. Here's an example:

```dart
var firstQuery = new Query<Post>()
  ..pageBy((p) => p.dateCreated, QuerySortOrder.descending)
  ..fetchLimit = 10;

var firstQueryResults = await firstQuery.fetch();

var oldestPostWeGot = firstQueryResults.last.dateCreated;
var nextQuery = new Query<Post>()
  ..pageBy((p) => p.dateCreated, QuerySortOrder.descending, boundingValue: oldestPostWeGot)
  ..fetchLimit = 10;
```

This query would fetch the newest 10 posts. Then, it fetches the next 10 after skipping past all of the ones newer than the oldest post it got in the first result set.

Conceptually, this works by sorting the rows in descending order - larger times are later times and come first, smaller times are earlier times and come later - and then grabs the first 10 from that ordered list. The next query sorts the rows again, but removes any newer than the oldest one in the last query. It takes the first 10 from that shortened list. If you were to search from oldest to newest, you'd reverse the sort order.

When paging, the query must have a `fetchLimit` - otherwise you're just sorting and returning every row. The `pageBy` method takes a closure to identify which property is being used to sort the rows. This closure will be passed an instance of `Post` and it must return one of its properties. This pattern of using a closure to identify a property like this is common to all of the advanced querying methods. The reason it is done this way is to let the analyzer help you catch errors in query building and the code completion to kick in and write faster code.

The next argument to `pageBy` defines the order the rows will be sorted in. Without a bounding value, `pageBy` returns rows starting from the beginning of the sorted list of rows. Therefore, when no bounding value is passed, the "first page" of rows is returned. With a bounding value, the query returns rows starting from the first row past the bounding value. The bounding value is not inclusive. For example, consider the following table and a `fetchLimit` of 2.

id|dateCreated
--|--------------
1|Jan 1 -- First Query Starts here
2|Jan 2
3|Jan 3
4|Jan 4

The first query would return `Jan 1` and `Jan 2`. In the next query, bounding value is set to `Jan 2`. The query would start grabbing rows from after Jan 2:

id | dateCreated
---|-------------
1 | Jan 1
2 | Jan 2
3 | Jan 3 -- Next Query Starts here
4 | Jan 4

In practice, this means passing the property value for the last object in the previous set. This is often accomplished by adding a query parameter to an endpoint that takes in a bounding value. (See `ManagedObjectController<T>` as an example.)

A `pageBy` query will return an empty list of objects when no more values are left. If the number of objects remaining in the last page are less than the `fetchLimit`, only those objects will be returned. For example, if there four more objects left and the `fetchLimit` is 10, the number of objects returned will be four.

You should index properties that will be paged by:

```dart
@ManagedColumnAttributes(indexed: true)
int pageableProperty;
```

### Filtering Results of a Fetch Operation

More often than not, fetching every row of a table doesn't make sense. Instead, the desired result is a specific object or set of objects matching some condition. Aqueduct offers two ways to perform this filtering, both of which translate to a SQL *where clause*.

The first option is the least prohibitive, the most prone to error and the most difficult to maintain: a `Query<T>.predicate`. A `QueryPredicate` is a `String` that is added to the underlying query's where clause. A `QueryPredicate` has two properties, a format string and a `Map<String, dynamic>` of parameter values. The `format` string can (and should) parameterize any input values. Parameters are indicated in the format string using the `@` token:

```dart
// Creates a predicate that would only include instances where some column "id" is less than 2
var predicate = new Predicate("id < @idVariable", {"idVariable" : 2});
```

The text following the `@` token may contain `[A-Za-z0-9_]`. The resulting where clause will be formed by replacing each token with the matching key in the parameters map. The value is not transformed in any way, so it must be the appropriate type for the property it is filtering by. If a key is not present in the `Map`, an exception will be thrown. Extra keys will be ignored.

A raw `QueryPredicate` like this one suffers from a few issues. First, predicates are *database specific* that is, after the values from the `parameters` are added to the `format` string, the resulting `String` is evaluated as-is by the underlying database. Perhaps more importantly, there is nothing to verify that the `QueryPredicate` refers to the appropriate column names or that the data in the `parameters` is the right type. This can cause chaos when refactoring code, where a simple name change to a property would break a query. This option is primarily intended to be used as a fallback if `Query<T>.where` is incapable of expressing the desired SQL.

The `where` property of a `Query<T>` is a much safer and more elegant way to build a query. The `where` property allows you to assign *matchers* to the properties of a `ManagedObject<T>`. A matcher applies a condition - like equal to or less than - to the property it is assigned to. (This follows the same Hamcrest matcher style that the Dart test framework uses.)

The `where` property of a `Query<T>` has the same properties as the managed object being fetched. For each property of `where` that is assigned a matcher will be added to the SQL where clause. Here's an example of a query that finds a `User` with an `id` equal to 1:

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo(1);
```

(The generated SQL here would be 'SELECT \_user.id, \_user.name, ... FROM \_user WHERE \_user.id = 1'.)

All matchers are created using one of the `where` top-level methods in Aqueduct. Other examples are `whereGreaterThan`, `whereBetween`, and `whereIn`. Every matcher set on a `where` is combined using logical 'and'. In other words, the following query will find all users whose `name` is "Bob" *and* `email` is not null:

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo("Bob")
  ..where.email = whereNotNull;
```

There are a number of `where` methods for different logic and string comparisons, see the API reference for more.

Relationship properties can be have matchers, too. For example, the following query will fetch all parents who have children that are less than 10 years old:

```dart
var query = new Query<Parent>()
  ..where.children.haveAtLeastOneWhere.age = whereLessThan(10);
```

When building `where` with relationship properties, there are some important things to understand. First, the values for any relationship properties are not returned in the results. In the previous query, that means that a list of `Parent`s would be returned - but their `children` property wouldn't be populated. (To actually include relationship values, the next section talks about `joinOne` and `joinMany`.)

Most `where`s that match on relationship properties will trigger a SQL join. This is a more expensive query than fetching from a single row. The only time a relationship matcher doesn't incur a SQL join is when matching the value of a foreign key column. That is, a belongs-to relationship property where we're only checking the primary key of the related object. There are two ways of doing this:

```dart
var preferredQuery = new Query<Child>()
  ..where.parent = whereRelatedByValue(23);

var sameQuery = new Query<Child>()
  ..where.parent.id = whereEqualTo(23);
```

The first query is preferred because it's clear to the reader what's happening. A query can be filtered by whether or not it has a value for its relationships. For example, the following queries return people with and without children:

```dart
var peopleWithoutChildren = new Query<Person>()
  ..where.children = whereNull;

var peopleWithChildren = new Query<Person>()
  ..where.children = whereNotNull;
```

The only matchers that can be applied directly to a relationship property are the three shown in these examples: `whereRelatedByValue`, `whereNull` and `whereNotNull`. Properties of a relationship property, i.e. `where.parent.age = whereGreaterThan(40)`, don't have these restrictions.

You can access relationship properties of relationships, too:

```dart
var childrenWithDoctorParents = new Query<Child>()
  ..where.parent.job.title = whereEqualTo("Doctor");
```

You can match belongs to or has one relationships by just assigning matchers to their properties. A has-many relationship, however, is a `ManagedSet<T>`. When matching on properties of a has-many relationship, you have to access their `haveAtLeastOneWhere` property. The type of this property is the type of object in the `ManagedSet<T>`, so it will have the properties of that type. To repeat the example above:

```dart
var query = new Query<Parent>()
  ..where.children.haveAtLeastOneWhere.age = whereLessThan(10);
```

The name here is important. The filter is applied to the returned `Parent`s - if a parent doesn't have a child that is younger than 10, it will be removed from the result set. If just one of a parent's children is less than 10, it will be included. There is currently no support for checking the number of objects in the relationship.

### Including Relationships in a Fetch (aka, Joins)

A `Query<T>` can also fetch relationship properties. This allows queries to fetch entire model graphs and reduces the number of round-trips to a database. (This type of fetch will execute a SQL LEFT OUTER JOIN.)

By default, relationship properties are not fetched in a query and therefore aren't included in an object's `asMap()`. For example, consider the following two `ManagedObject<T>`s, where a `User` has-many `Task`s:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @managedPrimaryKey int id;

  String name;
  ManagedSet<Task> tasks;  
}

class Task extends ManagedObject<_Task> implements _Task {}
class _Task {
  @managedPrimaryKey int id;

  @ManagedColumnAttributes(#tasks)
  User user;

  String contents;
}
```

A `Query<User>` will fetch the `name` and `id` of each `User`. A `User`'s `tasks` are not fetched, so the data returned looks like this:

```dart
var q = new Query<User>();
var users = await q.fetch();

users.first.asMap() == {
  "id": 1,
  "name": "Bob"
}; // yup
```

The method `joinMany()` will tell a `Query<T>` to also include a particular has-many relationship, here, a user's `tasks`:

```dart
var q = new Query<User>()
  ..joinMany((u) => u.tasks);
var users = await q.fetch();

users.first.asMap() == {
  "id": 1,
  "name": "Bob",
  "tasks": [
      {"id": 1, "contents": "Take out trash", "user" : {"id": 1}},
      ...
  ]
}; // yup
```

Notice that the `tasks` are in fact included in this query. The argument to `joinMany` is a closure that must return a `ManagedSet<T>` property of the object being queried. The values for each task is the default set of properties as though a `Query<Task>` was executed. However, this can be modified.

The method `joinMany()` actually returns a new `Query<T>`, where `T` is the type of object in the relationship property. That is, the above code could also be written as such:

```dart
var q = new Query<User>();

// type annotation added for clarity
Query<Task> taskSubQuery = q.joinMany((u) => u.tasks);
```

Just like any other `Query<T>`, the set of returning properties can be modified through `returningProperties`:

```dart
var q = new Query<User>()
  ..returningProperties((u) => [u.id, u.name]);

q.joinMany((u) => u.tasks)  
  ..returningProperties((t) => [t.id, t.contents]);
```

When joining on a has-one or a belongs-to relationship, use `joinOne()` instead of `joinMany()`:

```dart
var q = new Query<Task>()
  ..joinOne((t) => t.user);
var results = await q.fetch();

results.first.asMap() == {
  "id": 1,
  "contents": "Take out trash",
  "user": {
    "id": 1,
    "name": "Bob"
  }
}; // yup
```

Notice that the results of this query include all of the details for a `Task`'s `user` - not just its `id`.

A subquery created through `joinOne` or `joinMany` can also be filtered through its `where`. For example, the following query would return user's named 'Bob' and their overdue tasks only:

```dart
var q = new Query<User>()
  ..where.name = whereEquals("Bob");

q.joinMany((u) => u.tasks)  
  ..where.overdue = whereEqualTo(true);
```

Note that the `where` property on the subquery is an instance of `Task`, whereas `where` on the `User` query is `User`.

More than one join can be applied to a query, and subqueries can be nested. So, this is all valid, assuming the relationship properties exist:

```dart
var q = new Query<User>()
  ..joinOne((u) => u.address);

q.joinMany((u) => u.tasks)
  ..joinOne((u) => u.location);
```

This would fetch all users, their addresses, all of their tasks, and the location for each of their tasks. You'd get a nice sized tree of objects here.

It's important to understand how objects are filtered when using `where` and subqueries. Matchers applied to the top-level query will filter out those types of objects. A `where` on a subquery has no impact on the number of objects returned at the top-level. Let's say there were 10 total users, each with 10 total tasks. The following query would always return 10 user objects, but each user's `tasks` wouldn't necessarily contain all 10:

```dart
var q = new Query<User>();

q.joinMany((u) => u.tasks)
  ..where.overdue = whereEqualTo(true);
```

However, the following query would return less than 10 users, but for each user returned, they would have all 10 of their tasks:

```dart
var q = new Query<User>()
  ..where.name = whereEqualTo("Bob")
  ..joinMany((u) => u.tasks);
```

Note that a query will always fetch the primary key of all objects, even if it is omitted in `returningProperties`.
