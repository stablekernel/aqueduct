# Advanced Queries: Filtering, Joins, Paging and Reduce

## Paging Fetched Result Sets

In larger data sets, it may make sense to only return a portion of rows from a database. For example, in a social media application, a user could have thousands of pieces of content they had created over many years. The likely use case for fetching their content would be to grab only the most recent content, and only grab earlier content as necessary. Aqueduct has two mechanisms in `Query<T>` for building queries that can fetch a subset of rows within a certain range.

Naive paging can be accomplished using the `fetchLimit` and `offset` properties of a `Query<T>`. For example, if a table contains 100 rows, and you would like to grab 10 at a time, each query would have a value of 10 for its `fetchLimit`. The first query would have an `offset` of 0, then 10, then 20, and so on. Especially when using `sortBy`, this type of paging can be effective. One of the drawbacks to this type of paging is that it can skip or duplicate rows if rows are being added or deleted between fetches.

![Paging Error](../img/paging.png)

For example, consider the seven objects above that are ordered by time. If we page by two objects at a time (`fetchLimit=2`) starting at the first item (`offset=0`), our first result set is the first two objects. The next page is the original offset plus the same limit - we grab the next two rows. But before the next page is fetched, a new object is inserted and its at an index that we already fetched. The next page would return `3:00pm` again. A similar problem occurs if a row is deleted when paging in this way.

It is really annoying for client applications to have to check for and merge duplicates. Another paging technique that doesn't suffer from this problem relies on the client sending a value from the last object in the previous page, instead of an offset. So in the above example, instead of asking for offset 2 in the second query, it'd send the value `1:30pm`. The query filters out rows with a value less than the one it was sent, orders the remaining rows and then fetches the newest from the top.

`Query.pageBy` uses this technique. Its usage is similar to `sortBy`:

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

When paging, the query must have a `fetchLimit` - otherwise you're just sorting and returning every row. The `pageBy` method takes a closure to identify which property is being used to sort the rows. The closure is passed an instance of `Post` and it returns one of its properties. (This pattern of using a closure to identify a property like this is common to all of the advanced querying methods and is described elsewhere in this document.) The second argument to `pageBy` defines the order the rows will be sorted in.

When you first start paging, you don't have any results yet, so you can't send a value from the last result set. In this case, the `boundingValue` of `pageBy` is null - meaning start from the beginning. Once the first set has been fetched, the `boundingValue` is the value of the paging property in the last object returned.

This is often accomplished by adding a query parameter to an endpoint that takes in a bounding value. (See `ManagedObjectController<T>` as an example.)

A `pageBy` query will return an empty list of objects when no more values are left. If the number of objects remaining in the last page are less than the `fetchLimit`, only those objects will be returned. For example, if there four more objects left and the `fetchLimit` is 10, the number of objects returned will be four.

You should index properties that will be paged by:

```dart
@Column(indexed: true)
int pageableProperty;
```

## Filtering Results of a Fetch Operation

Fetching every row of a table usually doesn't make sense. Instead, we want a specific object or a set of objects matching some condition.

`Query.where` is a safe and  elegant way to build a query. The `where` property allows you to assign *matchers* to the properties of a `ManagedObject<T>`. A matcher applies a condition - like equal to or less than - to the property it is assigned to. (This follows the same Hamcrest matcher style that the Dart test framework uses.)

`Query.where` is the same type as the object being fetched. For each property of `where` that is assigned a matcher, an expression will be added to the SQL where clause. Here's an example of a query that finds a `User` with an `id` equal to 1:

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo(1);
```

(The generated SQL here would be 'SELECT \_user.id, \_user.name, ... FROM \_user WHERE \_user.id = 1'.)

All matchers begins with the word `where`. Other examples are `whereGreaterThan`, `whereBetween`, and `whereIn`. Every matcher set on a `where` is combined using logical 'and'. In other words, the following query will find all users whose `name` is "Bob" *and* `email` is not null:

```dart
var query = new Query<User>()
  ..where.id = whereEqualTo("Bob")
  ..where.email = whereNotNull;
```

There are `where` methods for other operators and string comparisons, see the API reference for more.

Relationship properties can be have matchers, too. For example, the following query will fetch all parents who have children that are less than 10 years old:

```dart
var query = new Query<Parent>()
  ..where.children.haveAtLeastOneWhere.age = whereLessThan(10);
```

When building `where` with relationship properties, there are some important things to understand. First, the values for any relationship properties are not returned in the results. In the previous query, that means that a list of `Parent`s would be returned - but their `children` property wouldn't be populated. (To actually include relationship values, the next section talks about `join`.)

Most matchers applied to a relationship property will incur a SQL join, which can be more expensive than a typical fetch. The only time a relationship matcher doesn't incur a SQL join is when matching the value of a foreign key column. That is, a belongs-to relationship property where we're only checking the primary key of the related object. There are two ways of doing this:

```dart
var preferredQuery = new Query<Child>()
  ..where.parent = whereRelatedByValue(23);

var sameQuery = new Query<Child>()
  ..where.parent.id = whereEqualTo(23);
```

The `whereRelatedByValue` approach is preferred because it's clear to the reader what's happening. A query can be filtered by whether or not it has a value for its relationships. For example, the following queries return people with and without children:

```dart
var peopleWithoutChildren = new Query<Person>()
  ..where.children = whereNull;

var peopleWithChildren = new Query<Person>()
  ..where.children = whereNotNull;
```

The only matchers that can be applied directly to a relationship property are the three shown in these examples: `whereRelatedByValue`, `whereNull` and `whereNotNull`. Properties of a relationship property, i.e. `where.parent.age = whereGreaterThan(40)`, don't have these restrictions.

You can access relationship properties of relationships, too. The following would fetch every child whose parent is a doctor.

```dart
var childrenWithDoctorParents = new Query<Child>()
  ..where.parent.job.title = whereEqualTo("Doctor");
```

When assigning matchers to the properties of has-many relationships, you may use the `haveAtLeastOneWhere` property. For example, the following returns all parents who have at least one child that is under 10 years old - but they could have other children that are not:

```dart
var query = new Query<Parent>()
  ..where.children.haveAtLeastOneWhere.age = whereLessThan(10);
```

The filter is applied to the returned `Parent`s - if a parent doesn't have a child that is younger than 10, it will be removed from the result set. If just one of a parent's children is less than 10, it will be included. No children are fetched, either.

## Including Relationships in a Fetch (aka, Joins)

A `Query<T>` can also fetch relationship properties. This allows queries to fetch entire model graphs and reduces the number of round-trips to a database. (This type of fetch will execute a SQL LEFT OUTER JOIN.)

By default, relationship properties are not fetched in a query and therefore aren't included in an object's `asMap()`. For example, consider the following two `ManagedObject<T>`s, where a `User` has-many `Task`s:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey int id;

  String name;
  ManagedSet<Task> tasks;  
}

class Task extends ManagedObject<_Task> implements _Task {}
class _Task {
  @primaryKey int id;

  @Column(#tasks)
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

The method `join()` will tell a `Query<T>` to also include a particular has-many relationship, here, a user's `tasks`:

```dart
var q = new Query<User>()
  ..join(set: (u) => u.tasks);
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

Notice that the `tasks` are in fact included in this query.  When joining a has-many relationship, the `set:` argument is given a closure that returns a `ManagedSet<T>` property of the type being queried.

The method `join()` actually returns a new `Query<T>`, where `T` is the type of object in the relationship property. That is, the above code could also be written as such:

```dart
var q = new Query<User>();

// type annotation added for clarity
Query<Task> taskSubQuery = q.join(set: (u) => u.tasks);
```

Just like any other `Query<T>`, the set of returning properties can be modified through `returningProperties`:

```dart
var q = new Query<User>()
  ..returningProperties((u) => [u.id, u.name]);

q.join(set: (u) => u.tasks)  
  ..returningProperties((t) => [t.id, t.contents]);
```

When joining on a has-one or a belongs-to relationship, use `join(object:)` instead of `join(set:)`:

```dart
var q = new Query<Task>()
  ..join(object: (t) => t.user);
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

Notice that the results of this query include all of the details for a `Task.user` - not just its `id`.

A subquery created through `join` can also be filtered through its `where` property. For example, the following query would return user's named 'Bob' and their overdue tasks only:

```dart
var q = new Query<User>()
  ..where.name = whereEquals("Bob");

q.join(set: (u) => u.tasks)  
  ..where.overdue = whereEqualTo(true);
```

Note that the `where` property on the subquery is an instance of `Task`, whereas `where` on the `User` query is `User`. More on that in a bit.

More than one join can be applied to a query, and subqueries can be nested. So, this is all valid, assuming the relationship properties exist:

```dart
var q = new Query<User>()
  ..join(object: (u) => u.address);

q.join(set: (u) => u.tasks)
  ..join(object: (u) => u.location);
```

This would fetch all users, their addresses, all of their tasks, and the location for each of their tasks. You'd get a nice sized tree of objects here.

It's important to understand how objects are filtered when using `where` and subqueries. Matchers applied to the top-level query will filter out those types of objects. A `where` on a subquery has no impact on the number of objects returned at the top-level.

Let's say there were 10 total users, each with 10 total tasks. The following query returns all 10 user objects, but each user's `tasks` would only contains those that are overdue. So a user might have 0, 1, or 10 tasks returned - even though there are a total of 10 available.

```dart
var q = new Query<User>();

q.join(set: (u) => u.tasks)
  ..where.overdue = whereEqualTo(true);
```

However, the following query would return less than 10 users, but for each user returned, they would have all 10 of their tasks:

```dart
var q = new Query<User>()
  ..where.name = whereEqualTo("Bob")
  ..join(set: (u) => u.tasks);
```

Note that a query will always fetch the primary key of all objects, even if it is omitted in `returningProperties`.

## Reduce Functions (aka, Aggregate Functions)

Queries can also be used to perform functions like `count`, `sum`, `average`, `min` and `max`. Here's an example:

```dart
var query = new Query<User>();
var numberOfUsers = await query.reduce.count();
```

For reduce functions that use the value of some property, a property selector is used to identify that property.

```dart
var averageSalary = await query.reduce.sum((u) => u.salary);
```

Any values configured in a `Query<T>` also impact the `reduce` function. For example, applying a `Query.where` and then executing a `sum` function will only sum the rows that meet the criteria of the where clause:

```dart
var query = new Query<User>()
  ..where.name = whereEqualTo("Bob");
var averageSalaryOfPeopleNamedBob = await query.reduce.sum((u) => u.salary);
```

## Fallbacks

You may always execute arbitrary SQL with `PersistentStore.execute`. Note that the objects returned will be a `List<List<dynamic>>` - a list of rows, for each a list of columns.

You may also provide raw WHERE clauses with `Query.predicate`. A `QueryPredicate` is a `String` that is set as the query's where clause. A `QueryPredicate` has two properties, a format string and a `Map<String, dynamic>` of parameter values. The `format` string can (and should) parameterize any input values. Parameters are indicated in the format string using the `@` token:

```dart
// Creates a predicate that would only include instances where some column "id" is less than 2
var predicate = new QueryPredicate("id < @idVariable", {"idVariable" : 2});
```

The text following the `@` token may contain `[A-Za-z0-9_]`. The resulting where clause will be formed by replacing each token with the matching key in the parameters map. The value is not transformed in any way, so it must be the appropriate type for the column. If a key is not present in the `Map`, an exception will be thrown. Extra keys will be ignored.
