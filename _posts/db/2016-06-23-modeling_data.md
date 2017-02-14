---
layout: page
title: "Modeling Data"
category: db
date: 2016-06-20 10:35:56
order: 2
---

In Aqueduct, data from a database is represented by *managed objects*. A managed object is an instance of some subclass of `ManagedObject<T>`. Each instance represents a row in the database. Managed objects are declared like so:

```dart
class User extends ManagedObject<_User> implements _User {  
}

class _User {
  @managedPrimaryKey
  int id;

  String name;
}
```

Here, we have declared that there is a `User` type. An instance of `User` is an object that represents (or will represent) a row in a `_User` table. The `_User` table has two columns: a primary key integer named `id` and a string named `name`. This deserves an explanation.

The first class - `User` - is the type you will use in your application code - you will get instances of `User` from the database, you will create instances of `User` to insert them in the database, you will decode JSON from an HTTP request body into `User` instances and you will encode `User` instances into JSON in an HTTP response body. This class - referred to as an *instance type* - must extend `ManagedObject<T>`. The class `ManagedObject<T>` has behavior to make these tasks easier on the developer.

The second class - `_User` - declares the mapping to a database table. That is, it declares that there is a table named `_User` in the database with two columns, `id` and `name`. This class is referred to as a *persistent type*. A persistent type, by convention, is prefixed with an underscore. This is for two reasons. First, the underscore makes it can't be used in other files - because it shouldn't be. Second, some databases have predefined tables and you may want to have similarly named tables in your application. For example, there is a `user` table in PostgreSQL. The prefix makes it so you don't have a name collision with a predefined table. (Later in the guide, we'll go over how to name tables differently than the persistent type name, but this is rarely useful.)

A persistent type and instance type are always declared in pairs. The persistent type is used twice in the declaration of the instance type: as the type argument to `ManagedObject<T>` and as an interface the instance type implements. In the above example, `User` implements `_User`, therefore `User` has two properties: `id` and `name`. Let's say we create a new `User` instance and set its `name`:

```dart
var user = new User();
user.name = "Bob";
```

This is where `ManagedObject<T>` starts doing its job. Each `ManagedObject<T>` stores its values in an internal `Map`. The keys in this map are the names of the properties from the persistent type. When an accessor method on `User` is invoked, the values are fetched from or stored in that internal `Map`. The code in `ManagedObject<T>` *manages* the storage and validation of those values by ensuring they meet the definition in the persistent type.

The distinction between persistent type and instance type allows for many of the powerful features of Aqueduct, which are covered by other guides in this documentation.  For now, the key takeaway is that the persistent type must map directly to a database table - every property must correspond to a database column, and vice versa. Aqueduct has tools to generate database tables based on the declaration of persistent types in an application (see [Aqueduct Database Tool](../tools/db.html)).

### More on Persistent Types

Persistent types define the mapping between your managed objects and a database table. As each property in a persistent type represents a database column, the type of the property must be storable in a database. The following types are available as scalar properties on a persistent type:

* `int`
* `double`
* `String`
* `DateTime`
* `bool`

Properties that are one of these types are more referred to as the *attributes* of an entity. Properties that are references to other model objects - which we will see later - are called *relationships*. Collectively, attributes and relationships are called *properties*.

In addition to a type and name, each property can also have `ManagedColumnAttributes` that adds some details to the associated column. `ManagedColumnAttributes` are added as metadata to a property. For example, the following change to the `_User` persistent type adds a `String` `email` property which must be unique across all users:

```dart
class _User {
  @managedPrimaryKey
  int id;

  String name;

  @ManagedColumnAttributes(unique: true)
  String email;
}
```
There are eight configurable items available in the `ManagedColumnAttributes` class.

* `primaryKey` - Indicates that property is the primary key of the table represented by this persistent type. Must be one per persistent type.
* `databaseType` - Uses a more specific type for the database column than can be derived from the Dart type of the property. For example, you may wish to specify that an integer property is stored in a database column that holds an 8-byte integer, instead of the default 4-byte integer.
* `nullable` - Toggles whether or not this property can contain the null value.
* `defaultValue` - A default value for this property when inserted into a database without an explicit value.
* `unique` - Toggles whether or not this property must be unique across all instances of this type.
* `indexed` - Toggles whether or not this property's database column should be indexed for faster searching.
* `omitByDefault` - Toggles whether or not this property should be fetched from the database by default. Useful for properties like hashed passwords, where you don't want to return that information when fetching an account unless you explicitly want to check the password.
* `autoincrement` - Toggles whether or not the underlying database should generate a new value from a serial generator each time a new instance is inserted into the database.

By not specifying `ManagedColumnAttributes`, the default values for each of these possible configurations is used and the database type is inferred from the type of the property. This also means that all properties declared in a persistent type represent a column in a database table - even without `ManagedColumnAttributes` metadata.

Every persistent type must have at least one property with `ManagedColumnAttributes` where `primaryKey` is true. There is a convenience instance of `ManagedColumnAttributes` for this purpose, `@managedPrimaryKey`, which is equivalent to the following:

```dart
@ManagedColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

Also in the persistent type - and only the persistent type - you may override the name of the table by implementing a static method named `tableName` that returns the name of the table in a persistent type:

```dart
class _User {
  @managedPrimaryKey
  int id;

  String name;

  static String tableName() => "UserTable";
}
```

Note that the specific database driver determines whether or not the table name is case-sensitive or not. The included database driver for PostgreSQL automatically lowercases table names and is case-insensitive.

### ManagedObject<T>

Where persistent types simply declare a mapping to a database table, `ManagedObject<T>`s do the actual work of lugging data between HTTP clients, Aqueduct applications and databases.

Managed objects can be inserted into a database and fetched back from that database. They can be used to configure an update to a database row. They can read their values from a `Map` and write them into a `Map` - this `Map` can safely be encoded to or decoded from JSON or another transmission format. This allows `ManagedObject<T>`s to be exactly represented in an HTTP request or response. Managed objects also lay the foundation for building queries. Here's an example of a common lifecycle of a `ManagedObject<T>` subclass, `User`:

```dart
@httpPost createThing() async {
  // Construct User from HTTP request body JSON
  var userFromRequestBody = new User()
    ..readMap(requestBody);

  // Construct Query for inserting the user, using values from the request body.
  var insertQuery = new Query<User>()
    ..values = userFromRequestBody;

  // Execute insert, get User back from database
  var insertedUser = await insertQuery.insert();

  // Return response with inserted User serialized as JSON HTTP response body.
  return new Response.ok(insertedUser);
}
```

When getting managed objects from a database, each instance will represent one row. For example, consider the following table, and the previous example of `_User` and `User` types:

id|name
--|----
1|Bob
2|Fred

If this entire table were fetched, you'd get a `List<User>` as though you had written the following code:

```dart
var users = [
  new User()
    ..id = 1
    ..name = "Bob",

  new User()
    ..id = 2
    ..name = "Fred"
];
```

Managed objects may also declare additional properties and methods beyond those in its persistent type. Because these properties and methods are not part of the persistent type, they are *transient* - that is, their values are not stored in the database. Any method or property defined in a subclass of `ManagedObject<T>` is ignored when sending data to a database. This is different than properties in a persistent type, where every property explicitly maps to a database column. Here's an example:

```dart
class Video extends ManagedObject<_Video> implements _Video {
  bool get isRecent => return new DateTime.now().difference(uploadDate).inDays < 7;
}

class _Video {
  @managedPrimaryKey int id;
  DateTime uploadDate;

  /* more properties */
  ...
}
```

Each video has a persistent property that indicates when the video was uploaded. As a convenience, you'd like to be able to determine if a video is "recent" - that is, it has been uploaded in the last week. Adding an `isRecent` property to the persistent type doesn't make any sense, because that information can be derived from the existing upload date property. This is a good place to use a transient property.

By default, transient properties are not included when a `ManagedObject<T>` is written into or read from a `Map`. So when a `Video` is returned as JSON in an HTTP response - `isRecent` won't be in the HTTP body. However, this is just the default behavior and can easily be changed, though - see [Storage, Serialization and Deserialization](serialization.html) for more details.

### Modeling Managed Object Relationships

In addition to attributes, managed objects may also have properties that are other managed objects or collections of managed objects. These types of properties are called *relationships*. For example, in a social network application, a user may have many posts that they have created. A user, then, should have a property that is a list of posts. This is called a 'has-many' relationship, because a user can have many posts.

A user might also have a job, so the user type should also have a property that references their job. This is called a 'has-one' relationship, because a user can only ever have one job at a time (... work with me here).

These relationships are also properties declared in a persistent type. In the above examples, a user would look like this:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {  
  @primaryKey int id;
  String name;

  Job job;
  ManagedSet<Post> posts;
}
```

The type `ManagedSet` is what indicates that the relationship is has-many. A `ManagedSet` is a glorified `List` - it can do everything a `List` can do - but has some additional behavior to help manage relationships and build queries. The type argument - here, `Post` - must be another `ManagedObject<T>` subclass. That means there is also a `_Post` table. If the type of a property is a just a `ManagedObject<T>` subclass - like `Job` - the relationship is has-one. One thing to note here is that all things 'database related' are declared inside the persistent type. The persistent type declares the database table, attribute properties declare the columns the table has, and relationship properties declare relationships to other database tables.

The relationship properties in `_User` do not represent columns in a database - they represent *entire rows* in a database table. Relationships in the database are maintained by foreign key reference columns. Therefore, the types `Job` and `Post` must have a column that stores the foreign key to `_User`. These properties are declared like so:

```dart
class Post extends ManagedObject<_Post> implements _Post {}
class _Post {
  @managedPrimaryKey
  int id;
  String text;

  @ManagedRelationship(#posts)
  User user;
}

class Job extends ManagedObject<_Job> implements _Job {}
class _Job {
  @managedPrimaryKey
  int id;
  String title;

  @ManagedRelationship(#job)
  User user;
}
```


The properties `user` on both `_Post` and `_Job` have `ManagedRelationship` metadata and are the *inverses* of the `_User`'s `posts` and `job` properties. All relationships must have an inverse. In other words, if a `User` has `posts`, then a `Post` has a `user`. The first argument to `ManagedRelationship` is what links relationships together. For example, the value `#job` for a `Job`'s `user` indicates that the name of the property for a `User`'s job is `job`. Because tables can have multiple references to the same table, it's important that a distinction is made and therefore this value is required.

Because `user` has `ManagedRelationship` metadata in both `_Post` and `_Job`, it is said that `_Post`s and `_Job`s *belong to* `_User`. `_User`, on the other hand, *has one* `_Job` and *has many* `_Post`s. Relationships may not belong to each other, so only one side of a relationship property may have the `ManagedRelationship` metadata and that property cannot be a `ManagedSet<T>`.

In the underlying database, properties with `ManagedRelationship` metadata are actually a foreign key column. Therefore, `_Post` has three columns: `id`, `title` and `user_id`. Whereas `User` still only has two columns, `name` and `id`, even though it declares properties for `Job` and `Post`.

The types of relationship properties must always be the instance type, not the persistent type. In other words, `User`'s `job` is of type `Job`, not `_Job`.

When an application starts up, relationships are checked for integrity. This check ensures that relationships are two-sided and only one property has the `ManagedRelationship` metadata. If they do not, an exception will be thrown.

`ManagedRelationship` properties are always indexed; although this may change in the future to be configurable, but it will always be the default. Additionally, `ManagedRelationship` properties specify that the column is unique if the other side is a 'has-one' relationship. Because the `ManagedRelationship` property is actually a foreign key column, it may also define some extra configuration parameters: a delete rule and whether or not it is required.

By making `Post.user` required, we will require that every `Post` must have a user in order to be inserted into the database. This means that a `Post` cannot exist without a user (i.e., the foreign key may not be null),

```dart
class _Post {
  ...
  @ManagedRelationship(#posts, required: true)
  User user;
}
```

By changing the `Profile.user` delete rule to `RelationshipDeleteRule.cascade`, deleting a `User` will also delete its `Profile`:

```dart
class _Profile {
  ...
  @ManagedRelationship(#profile, onDelete: ManagedRelationshipDeleteRule.cascade)
  User user;
}
```

By default, the delete rule is `nullify` (it is the least destructive action) and required is `false`. If you try and set up a relationship where the `ManagedRelationship` is both `nullify` and `required`, you will get an exception during startup: if the foreign key column can't be null and deleting the related object would nullify the foreign key column... well, that wouldn't work.

When fetching managed objects from a database, there are rules on which relationship properties are fetched. By default, any 'has-one' or 'has-many' relationships are *not* fetched from the database:

```dart
var query = new Query<User>();
var user = await query.fetchOne();

var userMap = user.asMap();
userMap == {
  'id' : 1,
  'name' : 'Bob'
}; // does not contain 'profile' or 'posts'
```

In order to fetch these types of relationships, you must explicitly configure a `Query<T>` to include them, which executes a SQL join. This is covered in the [Executing Queries](executing_queries.html).

The `ManagedRelationship` property, however, will be fetched by default. But, the entire object is not fetched - only its primary key value:

```dart
var query = new Query<Job>();
var job = await query.fetchOne();

var jobMap = job.asMap();
jobMap == {
  'id' : 1,
  'title' : 'Programmer',
  'user' : {
    'id' : 1
  }
};
```

It is possible to configure a `Query<T>` that will fetch the full object in this case, too.
