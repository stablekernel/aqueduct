---
layout: page
title: "Modeling Data"
category: db
date: 2016-06-20 10:35:56
---

## Modeling Your Data

In Aqueduct, data from a database is represented by *model objects*. A model object is an instance of a `Model` subclass that you define in your application code. These subclasses are used to map a Dart object to a database row. Thus, every instance of a `Model` object in your application represents a row (or a row to be inserted) in a database. These subclasses are referred to as *entities*. For example, you may have an application with a `User` class that is a subclass of `Model`. This creates a User entity in your application, which maps to a user table in your database. When fetching rows from the user table, your application will receive instances of `User` that represent these rows.

An entity must have properties that correspond to the columns in the table it represents. An entity is actually made up of two classes: a *persistent type* and an *instance type*. The persistent type is a plain Dart class that defines the mapping to a database table and its columns. A instance type is the subclass of `Model`; instances of this type are used in an application.

Here's an example of a model and persistent type, which are always declared together:

```dart
class User extends Model<_User> implements _User {  
}

class _User {
  @primaryKey int id;

  String name;
}
```

This declares a User entity. The instance type here is `User` because it extends `Model`. The `Model` class provides storage for an object that is fetched from a database. It also handles serialization and deserialization so that a model object can be encoded or decoded into formats like JSON.

The type parameter for `Model` must be the entity's persistent type. Here, the persistent type is `_User`. (By convention, a persistent type is prefixed with an underscore.) The persistent type declares properties for every column that is actually on the database table this entity maps to. In this example, we are declaring that there is a table named *_User* and it has two columns, an integer primary key named `id` and a text column named `name`.

A instance type must also implement the interface of its persistent type. This allows the instance type to have accessor methods for each of the properties defined in its persistent type:

```dart
var user = new User();

user.id = 1;
user.name = "Bob";
```

Because the instance type implements the persistent type (as opposed to extending it), the inherited properties from the persistent type do not have instance storage. That is, the instance type only exposes accessors for each property, but does not have an instance variable to store those values. Instead, the instance type's superclass, `Model`, takes care of storage by overriding `noSuchMethod` to store and retrieve values from its `backingMap`. `Model` will make sure the type of a value is the type declared in the persistent type before storing it in the `backingMap`.

![image](../../images/modelBacking.png)

A persistent type is never instantiated, it simply declares which properties are actually stored in a database and their types. All entities must be declared in this two-class setup. In the long-run, this significantly cuts down on typing and properly differentiates between database-backed properties and functionality that a model object may expose on top of those values.

In order to use an entity in your application, it must be compiled into a `DataModel` [see inside_the_db.md]. A `DataModel` will create instances of `ModelEntity` that preprocess and validate the information described in your persistent and instance types at application startup.

### More on Persistent Types

Persistent types define the mapping between your code and a database table (and are often used to generate those tables in a database). As each property in a persistent type represents a database column, the type of the property must be storable in a database. The following types are available as primitive properties on a persistent type:

* int
* double
* String
* DateTime
* bool

Properties that are one of these types are more specifically referred to the *attributes* of an entity. (Properties that are references to other model objects are called *relationships*. Collectively, attributes and relationships are called properties.)

In addition to a type and name, each property can also have `ColumnAttributes` that further specifies the corresponding column. `ColumnAttributes` is added as metadata to a property. For example, the following change to the `_User` persistent type adds a `String` `email` property which must be unique across all users:

```dart
class _User {
  @primaryKey int id;
  String name;

  @ColumnAttributes(unique: true)
  String email;
}
```
There are eight configurable items available in the `ColumnAttributes` class.

* `primaryKey` - Indicates that property is the primary key of the table represented by this persistent type. Must be one per persistent type.
* `databaseType` - Uses a more specific type for the database column than can be derived from the Dart type of the property. For example, you may wish to specify that an integer property is stored in a database column that holds an 8-byte integer, instead of the default 4-byte integer.
* `nullable` - Toggles whether or not this property can contain the null value.
* `defaultValue` - A default value for this property when inserted into a database without an explicit value.
* `unique` - Toggles whether or not this property must be unique across all instances of this type.
* `indexed` - Toggles whether or not this property's database column should be indexed for faster searching.
* `omitByDefault` - Toggles whether or not this property should be fetched from the database by default. Useful for properties like hashed passwords, where you don't want to return that information when fetching an account unless you explicitly want the check the password.
* `autoincrement` - Toggles whether or not the underlying database should generate a new value from a serial generator each time a new instance is inserted into the database.

By not specifying `ColumnAttributes`, the default values for each of these possible configurations is used and the database type is inferred from the type of the property.

Every persistent type must have at least one property with `ColumnAttributes` where `primaryKey` is true. There is a convenience instance of `ColumnAttributes` for this purpose, `@primaryKey`, which is equivalent to the following:

```dart
@ColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
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

### Instance Types

In using model objects in your application code, you will always use an entity's instance type. Model objects can be transferred to and from a database to insert or fetch data. Model objects can also read their properties from a `Map`, oftentimes from JSON data in an HTTP request body. Model objects also know how to serialize themselves back into a `Map`, so they can be used as an HTTP response body. Additionally, model objects are used to help build queries in a safe way. The following code snippet is a pretty common usage of a model object:


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

When getting model objects from a database, each instance will represent one row. For example, consider the following table, and the previous example of `_User` and `User` persistent and instance types:

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

Instance types may also define properties and methods on top of those it implements from its persistent type. Because these properties and methods are not part of the persistent type, they are *transient* - that is, they are not stored in the database. Any method or property defined on an instance type is ignored when used in a `Query`. This is in contrast to a persistent type, where every property explicitly maps to a database column.

It is often the case that you have a method or property on the instance type that makes some operation more convenient. For example, consider an entity that represented a video on a video sharing site. Each video has a persistent property that indicates when the video was uploaded. As a convenience, you'd like to be able to determine if a video instance is "recent" - that is, it has been uploaded in the last week. Adding a `isRecent` property to the persistent type doesn't make any sense, because that information can be derived from the existing upload date property. Thus, its a good use of a transient property:

```dart
class Video extends Model<_Video> implements _Video {
  bool get isRecent => return new DateTime.now().difference(uploadDate).inDays < 7;
}

class _Video {
  @primaryKey int id;
  DateTime uploadDate;
  ...
}
```

Note that, by default, transient properties are not serialized or deserialized, and are not `attributes` of their entity.

It is important to understand that a `Model` is a effectively a wrapper around a `Map<String, dynamic>`. This `Map` is the *backing* of the `Model` object. A `Model` object's values are stored in this `Map` - when you access a property of a model object, the name of the property is transformed into a `String` key in the backing map. This is why the instance type *implements* its persistent type - the actual storage for the properties are in this backing map, inherited from `Model`. The `Model` class implements `noSuchMethod` to set and get data from its backing map when an accessor is invoked on a `Model` subclass.

### Modeling Model Object Relationships

In addition to attributes, model objects may also have properties that are other model objects or collections of other model objects. These types of properties are called *relationships*. For example, in a social network application, a user may have many posts that they have created. A user, then, should have a property that is a list of posts. This is called a 'hasMany' relationship, because a user can have many posts.

A user might also have an associated profile, so it should also have a property that is an instance of some profile class. This is called a 'hasOne' relationship, because a user can only ever have one profile.

These relationships are declared in the persistent type of a model. In the above examples, a user would look like this:

```dart
class User extends Model<_User> implements _User {}
class _User {  
  @primaryKey int id;
  String name;
  Profile profile;
  OrderedSet<Post> posts;
}
```

An `OrderedSet` is what indicates that the relationship is hasMany. An `OrderedSet` is a glorified `List` - it can do everything a `List` can do - but has some additional behavior to help manage relationships and build queries.

Relationship properties do *not* map to columns in the database, but actually map to entire rows in some other table in a database. The type of a relationship property must be the instance type of an entity (as opposed to the persistent type).

All relationships of an entity must have a inverse relationship property on the destination entity. If a user has posts, then posts have a user. If a user has a profile, then a profile has a user. Thus, the `Post` and `Profile` entities both must have a property that is a `User`. Inverse relationship properties, like relationship properties, are declared in the entity's persistent type. Thus, the Post and Profile entities would be declared like so:

```dart
class Post extends Model<_Post> implements _Post {}
class _Post {
  @primaryKey int id;
  String text;

  @RelationshipInverse(#posts)
  User user;
}

class Profile extends Model<_Profile> implements _Profile {}
class _Profile {
  @primaryKey int id;
  String profilePhotoURL;

  @RelationshipInverse(#profile)
  User user;
}
```

The `RelationshipInverse` metadata is the special addition here. This accomplishes two things. First, the `RelationshipInverse` property is actually a column in the database: it is a foreign key to the other entity's table. In SQL databases, relationships are maintained through foreign key references. By specifying `RelationshipInverse`, you get to pick which table has the foreign key.

![RelationshipInverse](../../images/relationshipBacking.png)

Additionally, the first argument to `RelationshipInverse` allows you to pick the relationship property on the other entity that this property is inversely related to. For example, a User entity could potentially have two relationships with posts: posts they've created and posts that have queued for future posting. The Post table must have two foreign key columns to keep track of whether or not a User has already posted it or simply queued it. This `Symbol` for the property on the other side of the relationship makes this link.

Finally, the type of the inverse property must be the other entity's instance type.

During `DataModel` compilation to generate `ModelEntity`s, inverses are checked for integrity by ensuring that the `RelationshipInverse` symbol and the types of the relationship properties match. If they do not, the `DataModel` will throw an exception.

`RelationshipInverse` properties are always indexed; although this may change in the future to be configurable, but it will always be the default. Additionally, inverse properties are unique if the other side is a 'hasOne' relationship. Because the `RelationshipInverse` property is actually a foreign key column, it may also define some extra configuration parameters: a delete rule and whether and whether or not it is required.

By making the Post entity's `user` required, we will require that every `Post` must have a user in order to be inserted into the database. This means that a `Post` cannot exist without a user (i.e., the foreign key may not be null),

```dart
class _Post {
  ...
  @RelationshipInverse(#posts, required: true)
  User user;
}
```

By changing the Profile's `user` delete rule to `RelationshipDeleteRule.cascade`, deleting a `User` will also delete its `Profile`:
```
class _Profile {
  ...
  @RelationshipInverse(#profile, deleteRule: RelationshipDeleteRule.cascade)
  User user;
}
```

By default, the delete rule is `nullify` (it is the least destructive action) and required is `false`. If you try and set up a relationship where the inverse property is both `nullify` and `required`, you will get a `DataModel` exception: if the foreign key column can't be null and deleting the related object would nullify the foreign key column... well, that wouldn't work.

When receiving model objects after fetching them from a database, there are rules on which relationship properties are fetched. By default, any 'hasOne' or 'hasMany' relationships are *not* fetched from the database:

```dart
var query = new Query<User>();
var user = await query.fetchOne();

var userBacking = user.backingMap;
userBacking == {
  'id' : 1,
  'name' : 'Bob'
}; // does not contain 'profile' or 'posts'
```

In order to fetch these types of relationships, you must explicitly configure a `Query` to include them. This is because this type of query is more expensive - it causes a SQL join to be performed. This is covered in the `Executing Queries` chapter. [in executing_queries.md]

The other side of a relationship - the property with `RelationshipInverse` - will be fetched by default. However, the entire related object is not fetched - only its `primaryKey` value. The remainder of its properties will not be present in the `backingMap`.

```dart
var query = new Query<Profile>();
var profile = await query.fetchOne();

var userBacking = profile.user.backingMap;
userBacking == {
  'id' : 1
}; // does not contain 'name', 'profile' or 'posts'
```
