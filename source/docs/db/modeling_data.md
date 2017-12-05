# Modeling Data

In Aqueduct, database tables are modeled by subclassing `ManagedObject<T>`. These are declared like so:

```dart
class User extends ManagedObject<_User> implements _User {  
}

class _User {
  @primaryKey
  int id;

  String name;
}
```

This declares a `User` type for use in application code. The `_User` type describes a table named `_User` in a database. The table has two columns, a primary key integer named `id` and a text column named `name`.

An instance of `User` represents a row in the `_User` table. When you fetch rows from the `_User` table, you will get instances of `User`. This type - referred to as the *instance type* of a managed object - must subclass `ManagedObject<T>`.

The type argument of `ManagedObject<T>` declares the table that backs instances of this type. The table definition type - `_User` - is called the *persistent type* of a managed object. Properties in the persistent type must have a corresponding column in the database. Properties in the instance type are not stored in a database and are called *transient*.

An instance type should implement its persistent type, e.g. `implements _User`. This allows `User` to have the properties `id` and `name`.

A persistent type, by convention, is prefixed with an underscore. This is for two reasons. First, the underscore makes it can't be used in other files - because it shouldn't be. Second, some databases have predefined tables and you may want to have similarly named tables in your application. For example, there is a `user` table in PostgreSQL. The prefix makes it so you don't have a name collision with a predefined table. (Later in the guide, we'll go over how to name tables differently than the persistent type name, but this is rarely useful.)

A `ManagedObject<T>` manages the storage and validation of properties that are stored in a database - i.e. the properties declared in the persistent type.

The distinction between persistent type and instance type allows for many of the powerful features of Aqueduct, which are covered by other guides. For now, the key takeaway is that the persistent type must map directly to a database table - every property must correspond to a database column, and vice versa. Aqueduct has tools to generate database tables based on the declaration of persistent types in an application (see [Aqueduct Database Tool](db_tools.md)).

### More on Persistent Types

Persistent types define the mapping between your managed objects and a database table. As each property in a persistent type represents a database column, the type of the property must be storable in a database. The following types are available as scalar properties on a persistent type:

* `int`
* `double`
* `String`
* `DateTime`
* `bool`
* Any `enum`

Properties that are one of these types are more referred to as the *attributes* of an entity. Properties that are references to other model objects - which we will see later - are called *relationships*. Collectively, attributes and relationships are called *properties*.

In addition to a type and name, each property can also have `Column` that adds some details to the associated column. `Column` are added as metadata to a property. For example, the following change to the `_User` persistent type adds a `String` `email` property which must be unique across all users:

```dart
class _User {
  @primaryKey
  int id;

  String name;

  @Column(unique: true)
  String email;
}
```
There are eight configurable items available in the `Column` class.

* `primaryKey` - Indicates that property is the primary key of the table represented by this persistent type. Must be one per persistent type.
* `databaseType` - Uses a more specific type for the database column than can be derived from the Dart type of the property. For example, you may wish to specify that an integer property is stored in a database column that holds an 8-byte integer, instead of the default 4-byte integer.
* `nullable` - Toggles whether or not this property can contain the null value.
* `defaultValue` - A default value for this property when inserted into a database without an explicit value.
* `unique` - Toggles whether or not this property must be unique across all instances of this type.
* `indexed` - Toggles whether or not this property's database column should be indexed for faster searching.
* `omitByDefault` - Toggles whether or not this property should be fetched from the database by default. Useful for properties like hashed passwords, where you don't want to return that information when fetching an account unless you explicitly want to check the password.
* `autoincrement` - Toggles whether or not the underlying database should generate a new value from a serial generator each time a new instance is inserted into the database.

By not specifying `Column`, the default values for each of these possible configurations is used and the database type is inferred from the type of the property. This also means that *all* properties declared in a persistent type represent a column in a database table - even without `Column` metadata.

Every persistent type must have at least one property with `Column` where `primaryKey` is true. There is a convenience instance of `Column` for this purpose, `@primaryKey`, which is equivalent to the following:

```dart
@Column(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

Also in the persistent type - and only the persistent type - you may override the name of the table by implementing a static method named `tableName` that returns the name of the table in a persistent type:

```dart
class _User {
  @primaryKey
  int id;

  String name;

  static String tableName() => "UserTable";
}
```

Note that the specific database driver determines whether or not the table name is case-sensitive or not. The included database driver for PostgreSQL automatically lowercases table names and is case-insensitive.

### Enum Type Persistent Properties

When a persistent property is an `enum` type, the enumeration is stored as a string in the database. Consider the following definition where a user can be an admin or a normal user:

```dart
enum UserType {
  admin, user
}

class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;
  UserType type;
}
```

Your code works be assigning valid enumeration cases to the `User.type` property:

```dart
var query = new Query<User>()
  ..values.name = "Bob"
  ..values.type = UserType.admin;
var bob = await query.insert();

query = new Query<User>()
  ..where.type = whereEqualTo(UserType.admin);
var allAdmins = await query.fetch();
```

In the underlying database, the `type` column is stored as a string. Its value is either "admin" or "user" - which is derived from the two enumeration case names. A enumerated type property has an implicit `Validate.oneOf` validator that asserts the value is one of the valid enumeration cases.

### ManagedObject<T>

Where persistent types simply declare a mapping to a database table, `ManagedObject<T>`s do the actual work of lugging data between HTTP clients, Aqueduct applications and databases.

Managed objects can be inserted into and fetched from a database. They can be used to configure an update to a database row. They can read their values from a `Map` and write them into a `Map` - this `Map` can safely be encoded to or decoded from JSON or another transmission format. This allows `ManagedObject<T>`s to be exactly represented in an HTTP request or response. Managed objects also lay the foundation for building queries. Here's an example of a common lifecycle of a `ManagedObject<T>` subclass, `User`:

```dart
@Operation.post()
Future<Response> createThing(@Bind.body() User user) async {
  // Construct Query for inserting the user, using values from the request body.
  var insertQuery = new Query<User>()
    ..values = user;

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
  @primaryKey int id;
  DateTime uploadDate;

  /* more properties */
  ...
}
```

Each video has a persistent property that indicates when the video was uploaded. As a convenience, you'd like to be able to determine if a video is "recent" - that is, it has been uploaded in the last week. Adding an `isRecent` property to the persistent type doesn't make any sense, because that information can be derived from the existing upload date property. This is a good place to use a transient property.

By default, transient properties are not included when a `ManagedObject<T>` is written into or read from a `Map`. When a `Video` is returned as JSON in an HTTP response, `isRecent` won't be in the HTTP body. However, this is just the default behavior and can easily be changed, though - see [Storage, Serialization and Deserialization](serialization.md) for more details.

You may also override a `ManagedObject<T>`s `asMap()` method to get to similar behavior:

```dart
class Video extends ManagedObject<_Video> implements _Video {
  Map<String, dynamic> asMap() {
    var m = super.asMap();
    m["isRecent"] = new DateTime.now().difference(uploadDate).inDays < 7;
    return m;
  }
}
```

### Modeling Managed Object Relationships

In addition to attributes, managed objects may also have properties that are other managed objects or collections of managed objects. These types of properties are called *relationships*. For example, in a social network application, a user may have many posts that they have created. A user, then, should have a property that is a list of posts. This is called a 'has-many' relationship, because a user can have many posts.

A user might also have a job, so the user type should also have a property that references their job. This is called a 'has-one' relationship, because a user can only ever have one job at a time.

Relationships are also properties declared in a persistent type. In the above examples, a user would look like this:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {  
  @primaryKey int id;
  String name;

  Job job;
  ManagedSet<Post> posts;
}
```

If the type of a property is a `ManagedObject<T>` subclass - like `Job` - the relationship is has-one.

The type `ManagedSet` is what indicates that the relationship is has-many. A `ManagedSet` is a glorified `List` - it can do everything a `List` can do - but has some additional behavior to help manage relationships and build queries. The type argument must be a `ManagedObject<T>` subclass.

One thing to note here is that all things 'database related' are declared inside the persistent type. The persistent type declares the database table, attribute properties declare the columns the table has, and relationship properties declare relationships to other database tables.

The relationship properties in `_User` do not represent columns in a database - they represent *entire rows* in a database table. Relationships in the database are maintained by foreign key constraints. Therefore, the types `Job` and `Post` must have a column that stores the primary key of a  `_User`. Let's look at `Job` first:

```dart
class Job extends ManagedObject<_Job> implements _Job {}
class _Job {
  @primaryKey
  int id;
  String title;

  @Relate(#job)
  User user;
}
```

`Job.user` is a relationship property because it is a `ManagedObject<T>` subclass. It is the *inverse* property of `User.job`. All relationship properties must have an inverse. In other words, if a user has a job, then a job has a user. The inverse is set up by adding `Relate` data to one of the relationship properties. The argument to `Relate` is the name of the property on the other type.

Only one side of the relationship may have `Relate` metadata. The side with this metadata is said to *belong to* the other side. Thus, a `Job` belongs to a `User` and a `User` has-one `Job`. The property with `Relate` metadata is represented by a foreign key column in the database. The table `_Job`, then, has three columns: `id`, `title` and `user_id`. The name `user_id` is generated by joining the name of the relationship property with the name of the primary key on the other object.

Setting the inverse of a has-many relationship is done in the same way, so `Post` would be declared like so:

```dart
class Post extends ManagedObject<_Post> implements _Post {}
class _Post {
  @primaryKey
  int id;
  String text;

  @Relate(#posts)
  User user;
}
```

The types of relationship properties must always be the instance type, not the persistent type. In other words, `User.job` is of type `Job`, not `_Job`.

When an application starts up, relationships are checked for integrity. This check ensures that relationships are two-sided and only one property has the `Relate` metadata. If they do not, an exception will be thrown.

`Relate` properties are always indexed; this may change in the future to be configurable, but it will always be the default. Additionally, the column backing `Relate` properties are unique if the other side is a 'has-one' relationship. Because the `Relate` property is actually a foreign key column, it may also define some extra configuration parameters: a delete rule and whether or not it is required.

By making `Post.user` required, we will require that every `Post` must have a user in order to be inserted into the database. This means that a `Post` cannot exist without a user (i.e., the foreign key may not be null),

```dart
class _Post {
  ...
  @Relate(#posts, required: true)
  User user;
}
```

By changing the `Job.user` delete rule to `RelationshipDeleteRule.cascade`, deleting a `User` will also delete its `Job`:

```dart
class _Job {
  ...
  @Relate(#job, onDelete: DeleteRule.cascade)
  User user;
}
```

By default, the delete rule is `DeleteRule.nullify` (it is the least destructive action) and required is `false`. If you try and set up a relationship where the `Relate` is both `DeleteRule.nullify` and `isRequired`, you will get an exception during startup: if the foreign key column can't be null and deleting the related object would nullify the foreign key column... well, that wouldn't work.

When fetching managed objects from a database, there are rules on which relationship properties are fetched. By default, any 'has-one' or 'has-many' relationships are *not* fetched from the database:

```dart
var query = new Query<User>();
var user = await query.fetchOne();

var userMap = user.asMap();
userMap == {
  'id' : 1,
  'name' : 'Bob'
}; // does not contain 'job' or 'posts'
```

In order to fetch these types of relationships, you must explicitly configure a `Query<T>` to include them, which executes a SQL join. This is covered in the [Executing Queries](executing_queries.md).

The `Relate` property, however, will be fetched by default. But, the entire object is not fetched - only its primary key value:

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
