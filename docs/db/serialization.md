# Storage, Serialization and Deserialization

In the previous chapter, you have seen that `ManagedObject<T>`s subclasses are responsible for representing database rows and can be encoded to or decoded from transmission formats like JSON or XML. This chapter explains the behavior of those transformations.

`ManagedObject<T>`s are created by reading JSON from a HTTP request body. Their values are often written to JSON in an HTTP response body. For these tasks, every `ManagedObject<T>` has the methods `readMap` and `asMap`. You'll likely invoke `readMap` often - you rarely have to invoke `asMap`, as some other mechanisms do this for you when returning and HTTP response. Here's an example of those two methods:

```dart
var userMap = {
    "id" : 1,
    "name" : "Bob"
};

var user = new User()..readMap(userMap);

var outUserMap = user.asMap();

userMap == outUserMap; // yup
```

Note that `ManagedObject<T>`s don't have anything to do with JSON, XML or some other format here. Other parts of Aqueduct manage moving data back and forth between JSON and `Map`s - `ManagedObject<T>` doesn't care about the actual format as long as it can work with `Map`s.

It's important to understand how `null` works when reading from or writing to a `Map` with a `ManagedObject<T>`. `User` has two properties, `id` and `name`, and in the previous code block, both of those properties were in the both the input and output `Map`. But what happens if `id` is not in the input map:

```dart
var userMap = {
  "name" : "Bob"
};

var user = new User()..readMap(userMap);

user.id == null; // yup
user.name == "Bob"; // yup

var outUserMap = user.AsMap();
outUserMap == {
  "name" : "Bob"
};
```

OK, so the `User` reads in the map without `id`, says the `id` is `null`, and when it transformed the `User` back to `Map`, remembered that `id` wasn't in there. But what about this, where `id` is in the input map, but its explicitly `null`:

```dart
var userMap = {
  "id" : null
  "name" : "Bob"
};

var user = new User()..readMap(userMap);

user.id == null; // yup
user.name == "Bob"; // yup

var outUserMap = user.asMap();
outUserMap == {
  "id" : null
  "name" : "Bob"
};
```

Here, because the value in the input map was explicitly `null` when read, `User` includes it in its output map. A `ManagedObject<T>` - like `User` here - makes the distinction between a value that is `null` and a value that it *doesn't have enough information about*. A property of a `ManagedObject<T>` can get set in three ways: its read from a map, its through an accessor method or its read from the database. In all three of these situations, not every property is available. For example, a database query may only fetch a subset of columns.

This is no more obvious than when just creating a brand new instance:

```dart
var user = new User();
user.id == null; // yup
user.name == null; // yup

user.asMap() == {}; // yup
```

A `ManagedObject<T>` will not include keys in its `asMap()` if it doesn't have a value for them. The value may exist somewhere else - like in the database - but if it doesn't have it, it won't include it. This distinction is useful information for clients of Aqueduct applications.

So what about values that are actually `null`? A property with the value `null` will be included in `asMap()` if its been read from the database, read using `readMap()` or explicitly assigned to a property. The following three user objects will all have `{"name": null}`:

```dart
var user1 = new User()
  ..id = 1
  ..name = null;

var user2 = new User()..readMap({
  "id": 2
  "name": null
});

var query = new Query<User>()
  ..where.id = whereEqualTo(3)
  ..where.name = whereNull;
var user3 = await query.fetchOne();
```

Note that any value that is returned from an accessor method that hasn't been populated in a `ManagedObject<T>` will be `null`. If using an object's values to perform some calculation, it's your job to know if the value has been fetched or not. (See `ManagedObject<T>.hasValueForProperty()` for how to check this at runtime.)

One last thing to note: if you wish to remove a value from a `ManagedObject<T>`s storage (and likewise, its `asMap()`), you may not simply set the property to `null`. This can only be accomplished with `ManagedObject<T>.removePropertyFromBackingMap()`.

It is helpful to think of a `ManagedObject<T>` as a proxy to a database row that may or may not exist yet, and may have less data than actually exists in the database row.

### Transient Properties and Serialization/Deserialization

By default, transient properties and getters - those declared in the subclass of `ManagedObject<T>` - are *not* included in the `asMap()`. (Setters are obviously not included, as you can't get a value from them.) To include a transient property or getter in `asMap()`, you may mark it with `@managedTransientOutputAttribute` metadata. Properties marked with this metadata will be included in the serialized `Map` if and only if they are not null. A good reason to use this feature is when you want to provide a value to the consumer of the API that is derived from one or more values in persistent type of the managed object:

```dart
class User extends ManagedObject<_User> implements _User {
  @managedTransientOutputAttribute
  String get fullName => "$firstName $lastName";
}

class _User {
  String firstName;
  String lastName;

  ...
}

var user = new User()
  ..firstName = "Bob"
  ..lastName = "Boberson";

var map = user.asMap();
map == {
  'firstName' : 'Bob',
  'lastName' : 'Boberson',
  'fullName' : 'Bob Boberson'
};

```

Transient properties may also be used as inputs when reading with `readMap()` by marking a property with `@managedTransientInputAttribute`. For example, consider how to handle user passwords. The persistent type - a direct mapping to the database - does not have a password property for security purposes. Instead, it has a password hash and a salt. An instance type could then define a password property, which automatically set the salt and hash of the password in the underlying persistent type:

```dart
class User extends ManagedObject<_User> implements _User {
  @managedTransientInputAttribute
  void set password(String pw) {
    salt = generateSalt();
    hashedPassword = hash(pw, salt);
  }
}
class _User {
  String salt;
  String hashedPassword;
  ...
}

var map = {
  'password' : 'mypassword'
};
var user = new User()..readMap(map);
var salt = user.salt; // 'somerandomstring'
var hashedPassword = user.hashedPassword; // 'somehashedstring'

var password = user.password; // Analyzer error - user.password doesn't exist!
```

On a related note, persistent properties are always included in `asMap()` by default, but can be omitted by adding `ManagedColumnAttributes` metadata with the `omitByDefault` option:

```dart
class _User {
  @ManagedColumnAttributes(omitByDefault: true)
  String salt;

  @ManagedColumnAttributes(omitByDefault: true)
  String hashedPassword;
  ...
}
```

A transient input attribute must be a setter or a property, just like an transient output attribute must be a getter or a property. For properties that are both inputs and outputs, you may use the metadata `@managedTransientAttribute`.

```dart
class User extends ManagedObject<_User> implements _User {
  @managedTransientAttribute
  String nickname; // shows up in asMap() and can be read from readMap()
}
```

Also, a separate getter and setter may exist for the same name to allow both input and output:

```dart
class User extends ManagedObject<_User> implements _User {
  @managedTransientInputAttribute
  void set transientValue(String s) {
    ...
  }

  @managedTransientOutputAttribute
  String get transientValue => ...;
}
```

Transient properties marked with these metadata *are* `attributes` in `ManagedEntity` (like scalar properties on the persistent type, but unlike other properties on an instance type).

### Serialization and Deserialization of Relationship Properties

Relationship properties - references to other `ManagedObject<T>` subclasses - can also be included in `asMap()` and read from `readMap()`, so long as the instance knows their value. Relationship properties are typically populated when executing a `Query<T>` with `joinOne()` or `joinMany()` - aka, a SQL JOIN.

If an object has a "has-one" or "belongs to" relationship property, its `asMap` will contain a nested `Map` representing the related object. For example, recall the `User` with a `job`:

```dart
var job = new Job()
  ..title = "Programmer";
var user = new User()
  ..name = "Bob"
  ..job = job;

var userMap = user.asMap();
userMap == {
  "id": 1,
  "name": "Bob",
  "job": {
    "id": 1
    "title": "Programmer"
  }
}; // yup
```

Notice that the names of the keys - including relationship properties and properties of the related object - all match the names of their declared properties.

It's important to note that "belongs to" relationships - those with `ManagedRelationship` metadata that represent foreign key columns - are always represented by `Map`s. When fetching an object with a from a database, the underlying foreign key column value is fetched by default. When that object's `asMap()` is invoked, the foreign key value is wrapped in a `Map`. The key to this `Map` is the primary key of the related object. For example:

```dart
var jobQuery = new Query<Job>();
var job = await jobQuery.fetchOne();

job.asMap() == {
  "id": 1,
  "title": "Programmer",
  "user": {
    "id": 1
  }
}; // yup
```

This behavior might be different than some ORMs, which would include a key that matches the name of the underlying database column where the value is simply the integer foreign key. That would look like this:

```dart
job.asMap() == {
  "id": 1,
  "title": "Programmer",
  "user_id": 1
}; // nope
```

Aqueduct treats relationships consistently and chooses not to expose any of the underlying database details to the API consumer. An iOS app, for example, shouldn't care - a relationship could be maintained by foreign key references or by witchcraft. The interesting piece to the API consumer is that job's have a user, and user's have a job.

"Has-many" relationships, which are represented as `ManagedSet<T>`s, are written as `List<Map>`s in `asMap()`.

```dart
var user = new User()
  ..id = 1;
  ..posts = new ManagedSet.from([
      new Post()..id = 2,
      new Post()..id = 3
  ]);

var userMap = user.asMap();
userMap == {
  'id' : 1,
  'posts' : [
    {
      'id' : 2
    },
    {
      'id' : 3
    }
  ]
};
```

It is important to note the potential for cyclic object graphs. Since all relationship properties are two-sided, the two properties in that relationship are references to one another. That is, you could do something like this:

```dart
identical(user.profile.user, user);
identical(user.posts.first.user, user);
```

When fetching objects from a database, this won't happen - Aqueduct will create multiple instances of the same row when necessary to avoid this. Therefore, the previous code snippet would not be true, but the following two statements that check the values inside those objects would be:

```
user.profile.user.id == user.id;

user.posts.first.user.id == user.id
```

While managed objects from a database will not have cyclic references, managed objects you instantiate yourself can if you mistakenly do so. When you invoke `asMap()` on a cyclic graph, you'll get a stack overflow error. It's best to avoid creating cyclic graphs altogether. For example:

```dart
// do:
var user = new User();
posts.forEach((p) {
  p.user = new User()..id = user.id;
});

// do not:
var user = new User();
posts.forEach((p) {
  p.user = user;
});
```

When reading the values of a `ManagedObject<T>` with `readMap()`, relationship properties must also be represented as nested `Map`s. Thus:

```dart
var userMap = {
  "id": 1,
  "name": "Bob",
  "posts": [
    {"id": 1, "text": "hello"}
  ]
};

var user = new User()..readMap(userMap);
user.posts == new ManagedSet<Post>[
  new Post()
    ..id = 1
    ..text = "hello"
]; // yup, other Post doesn't implement == to check property equality
```
