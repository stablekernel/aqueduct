---
layout: page
title: "Modeling Data"
category: db
date: 2016-06-20 10:35:56
order: 2
---

In Aqueduct, data from a database is represented by *managed objects*. A managed object is a subclass of `ManagedObject<T>` and stores its properties in a backing `Map`. Thus, a managed object *manages* its properties, instead of letting instance variables store data. This behavior allows for all sorts of functionality related to transferring data between HTTP requests, your application code and a database.

An instance of `ManagedObject<T>` represents a row in a database. Every managed object has a corresponding `ManagedEntity`. The entity is the description of the properties a `ManagedObject<T>` has. Each of these properties maps to a database column. Therefore, a `ManagedObject<T>` is to a database table row as a `ManagedEntity` is to a database table.

An managed object is actually made up of two classes: a *persistent type* and a subclass of `ManagedObject<T>`. The persistent type is a plain Dart class that defines the property to database column mapping. You don't use instances of the persistent type directly, instead, they are the type argument and interface for the managed object subclass. Both are declared together:

```dart
class User extends ManagedObject<_User> implements _User {  
}

class _User {
  @managedPrimaryKey int id;

  String name;
}
```

This declares a User type. An instance of `User` represents a row in the `_User` table. An instance of `User` may also be serialized so that it can be encoded into a format like JSON. Conversely, an instance of `User` can be created from a `Map<String, dynamic>` that has been decoded from JSON. This is true of all `ManagedObject<T>`s.

By convention, a persistent type is prefixed with an underscore - in this example, `_User`. The name of the table in the underlying database will be the name of the persistent type. The names of each property will be the names of the columns. In this example, we are declaring that there is a table named *_User* and it has two columns, an integer primary key named `id` and a text column named `name`.

A managed object type must also implement the interface of its persistent type. This allows the instance type to have accessor methods for each of the properties defined in its persistent type:

```dart
var user = new User();

user.id = 1;
user.name = "Bob";
```

Because managed objects only implement their persistent type - as opposed to extending it - they do not have instance variable storage for their persistent properties. When you set or get a property on a managed object, the accessor method invokes `noSuchMethod` in its superclass, `ManagedObject<T>`. This method has been overridden to set and get values from `ManagedObject.backingMap`. This mechanism will also validate types and values for properties. When a property can't be validated, this mechanism will throw an exception that `RequestController`s will interpret to return appropriate status codes to the HTTP client.

Because the instance type implements the persistent type (as opposed to extending it), the inherited properties from the persistent type do not have instance storage. That is, the instance type only exposes accessors for each property, but does not have an instance variable to store those values. Instead, the instance type's superclass, `Model`, takes care of storage by overriding `noSuchMethod` to store and retrieve values from its `backingMap`. `Model` will make sure the type of a value is the type declared in the persistent type before storing it in the `backingMap`.

Managed objects must be compiled into a `ManagedDataModel`. A `ManagedDataModel` will reflect on your application's code to find every `ManagedObject<T>` subclass and create instances of `ManagedEntity`. This allows Aqueduct classes like `Query<T>` and tools like database migration to successfully interact with a database. (See [Inside the DB](inside_the_db.html) for more details.)

### More on Persistent Types

Persistent types define the mapping between your managed objects and a database table (and are often used to generate those tables in a database). As each property in a persistent type represents a database column, the type of the property must be storable in a database. The following types are available as scalar properties on a persistent type:

* int
* double
* String
* DateTime
* bool

Properties that are one of these types are more specifically referred to the *attributes* of an entity. (Properties that are references to other model objects are called *relationships*. Collectively, attributes and relationships are called properties.)

In addition to a type and name, each property can also have `ManagedColumnAttributes` that further specifies the corresponding column. `ManagedColumnAttributes` is added as metadata to a property. For example, the following change to the `_User` persistent type adds a `String` `email` property which must be unique across all users:

```dart
class _User {
  @managedPrimaryKey int id;

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
* `omitByDefault` - Toggles whether or not this property should be fetched from the database by default. Useful for properties like hashed passwords, where you don't want to return that information when fetching an account unless you explicitly want the check the password.
* `autoincrement` - Toggles whether or not the underlying database should generate a new value from a serial generator each time a new instance is inserted into the database.

By not specifying `ManagedColumnAttributes`, the default values for each of these possible configurations is used and the database type is inferred from the type of the property.

Every persistent type must have at least one property with `ManagedColumnAttributes` where `primaryKey` is true. There is a convenience instance of `ManagedColumnAttributes` for this purpose, `@managedPrimaryKey`, which is equivalent to the following:

```dart
@ManagedColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

By convention, persistent types begin with an underscore, but there is nothing that prevents you from changing this. Bear in mind, the name of the persistent type will be the name of the corresponding database table (and some databases, like PostgreSQL, already have a table named 'user'). You may override the name of the table by implementing a static method that returns the name of the table in a persistent type:

```dart
class _User {
  @primaryKey int id;
  String name;

  static String tableName() {
    return "UserTable";
  }
}
```

Note that the specific database driver determines whether or not the table name is case-sensitive or not. The included database driver for PostgreSQL automatically lowercases table names and is case-insensitive.

### Managed Objects

Managed objects can be transferred to and from a database to insert, update or fetch data. Managed objects can also read their properties from a `Map`, oftentimes from JSON data in an HTTP request body. Managed objects also know how to serialize themselves back into a `Map`, so they can be used as an HTTP response body. Additionally, managed objects are used to help build queries in a safe way. The following code snippet is a pretty common usage of a managed object:


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

  // Return response with inserted User serialized as HTTP response body.
  return new Response.ok(insertedUser);
}
```

When getting managed objects from a database, each instance will represent one row. For example, consider the following table, and the previous example of `_User` and `User` persistent and instance types:

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

Managed objects may also define properties and methods on top of those it implements from its persistent type. Because these properties and methods are not part of the persistent type, they are *transient* - that is, they are not stored in the database. Any method or property defined in a subclass of `ManagedObject<T>` is ignored when used in a `Query<T>`. This is in contrast to a persistent type, where every property explicitly maps to a database column.

It is often the case that you have a method or property on the instance type that makes some operation more convenient. For example, consider an entity that represented a video on a video sharing site. Each video has a persistent property that indicates when the video was uploaded. As a convenience, you'd like to be able to determine if a video instance is "recent" - that is, it has been uploaded in the last week. Adding a `isRecent` property to the persistent type doesn't make any sense, because that information can be derived from the existing upload date property. Thus, its a good use of a transient property:

```dart
class Video extends ManagedObject<_Video> implements _Video {
  bool get isRecent => return new DateTime.now().difference(uploadDate).inDays < 7;
}

class _Video {
  @managedPrimaryKey int id;
  DateTime uploadDate;
  ...
}
```

Note that, by default, transient properties are not serialized or deserialized, and are not `attributes` of their entity. (See [Serialization and Deserialization](serialization.html) for more details.)

### Modeling Managed Object Relationships

In addition to attributes, managed objects may also have properties that are other managed objects or collections of managed objects. These types of properties are called *relationships*. For example, in a social network application, a user may have many posts that they have created. A user, then, should have a property that is a list of posts. This is called a 'has-many' relationship, because a user can have many posts.

A user might also have an associated profile, so it should also have a property that is an instance of some profile class. This is called a 'has-one' relationship, because a user can only ever have one profile.

These relationships are declared in a persistent type. In the above examples, a user would look like this:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {  
  @primaryKey int id;
  String name;

  Profile profile;
  ManagedSet<Post> posts;
}
```

An `ManagedSet` is what indicates that the relationship is has-many. An `ManagedSet` is a glorified `List` - it can do everything a `List` can do - but has some additional behavior to help manage relationships and build queries.

Relationship properties do *not* map to columns in the database, but actually map to entire rows in some other table in a database. The type of a relationship property must be a subclass of `ManagedObject<T>` (as opposed to the persistent type).

All relationships are two-sided. Therefore, an inverse relationship property must exist on the other managed object. If a user has posts, then posts have a user. If a user has a profile, then a profile has a user. Thus, the `Post` and `Profile` both must have a property that is a `User`. These types of properties are also declared in a persistent type:

```dart
class Post extends ManagedObject<_Post> implements _Post {}
class _Post {
  @managedPrimaryKey int id;
  String text;

  @ManagedRelationship(#posts)
  User user;
}

class Profile extends ManagedObject<_Profile> implements _Profile {}
class _Profile {
  @managedPrimaryKey int id;
  String profilePhotoURL;

  @ManagedRelationship(#profile)
  User user;
}
```

The `ManagedRelationship` metadata is the special addition here. This accomplishes two things. First, a property with `ManagedRelationship` is actually a column in the database: it is a foreign key to the other managed object's table. In SQL databases, relationships are maintained through foreign key references. By specifying `ManagedRelationship`, you get to pick which table has the foreign key.

Additionally, the first argument to `ManagedRelationship` specifies the relationship property on the other managed object. For example, a `User` could potentially have two relationships with posts: posts they've created and posts that have queued for future posting. The `Post` table must have two foreign key columns to keep track of whether or not a User has already posted it or simply queued it. This `Symbol` for the property on the other side of the relationship makes this link.

During `ManagedDataModel` compilation, relationships are checked for integrity by ensuring that they are two-sided and only one property has `ManagedRelationship` metadata. If they do not, an exception will be thrown.

`ManagedRelationship` properties are always indexed; although this may change in the future to be configurable, but it will always be the default. Additionally, `ManagedRelationship` properties are unique if the other side is a 'has-one' relationship. Because the `ManagedRelationship` property is actually a foreign key column, it may also define some extra configuration parameters: a delete rule and whether and whether or not it is required.

By making the `Post.user` required, we will require that every `Post` must have a user in order to be inserted into the database. This means that a `Post` cannot exist without a user (i.e., the foreign key may not be null),

```dart
class _Post {
  ...
  @ManagedRelationship(#posts, required: true)
  User user;
}
```

By changing the `Profile.user` delete rule to `RelationshipDeleteRule.cascade`, deleting a `User` will also delete its `Profile`:
```
class _Profile {
  ...
  @ManagedRelationship(#profile, onDelete: ManagedRelationshipDeleteRule.cascade)
  User user;
}
```

By default, the delete rule is `nullify` (it is the least destructive action) and required is `false`. If you try and set up a relationship where the `ManagedRelationship` is both `nullify` and `required`, you will get an exception: if the foreign key column can't be null and deleting the related object would nullify the foreign key column... well, that wouldn't work.

When fetching managed objects from a database, there are rules on which relationship properties are fetched. By default, any 'has-one' or 'has-many' relationships are *not* fetched from the database:

```dart
var query = new Query<User>();
var user = await query.fetchOne();

var userBacking = user.backingMap;
userBacking == {
  'id' : 1,
  'name' : 'Bob'
}; // does not contain 'profile' or 'posts'
```

In order to fetch these types of relationships, you must explicitly configure a `Query<T>` to include them. This is because this type of query is more expensive - it causes a SQL join to be performed. This is covered in the [Executing Queries](executing_queries.html).

The other side of a relationship - the property with `ManagedRelationship` - will be fetched by default. However, the entire related object is not fetched - only its primary key value. The remainder of its properties will not be present in the `backingMap`.

```dart
var query = new Query<Profile>();
var profile = await query.fetchOne();

var userBacking = profile.user.backingMap;
userBacking == {
  'id' : 1
}; // does not contain 'name', 'profile' or 'posts'
```
