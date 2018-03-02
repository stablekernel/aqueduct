# Storage, Serialization and Deserialization

In the previous chapter, you have seen that `ManagedObject<T>`s subclasses are responsible for representing database rows and can be encoded to or decoded from formats like JSON or XML. This chapter explains the behavior of those transformations.

`ManagedObject<T>` implements `HTTPSerializable` so that they can read from a `Map` or converted to a `Map`. A `ManagedObject<T>` can be passed as the body object of a `Response` and bound to `Bind.body` variables in `ResourceController`:

```dart
class UserController extends ResourceController {
  @Operation.post()
  Future<Response> createUser(@Bind.body() User user) async {
    var query = new Query<User>()
      ..values = user;

    return new Response.ok(await query.insert());
  }
}
```

Note that `ManagedObject<T>`s don't have anything to do with JSON, XML or some other format here. Other parts of Aqueduct manage moving data back and forth between JSON and `Map`s - `ManagedObject<T>` doesn't care about the transmission format as long as its a `Map` or `List<Map>`.


## Null Behavior

It's important to understand how `null` works when reading from or writing to a `Map` with a `ManagedObject<T>`. Consider the following managed object:

```dart
class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;
}
```

`User` has two properties, `id` and `name`. If we read a `User` from a `Map` that does not contain an `id` key, its `id` will be null. If we convert `User` to a `Map`, the key `id` will not be present:

```dart
var userMap = {
  "name" : "Bob"
};

var user = new User()..readFromMap(userMap);

user.id == null; // yup
user.name == "Bob"; // yup

var outUserMap = user.asMap();
outUserMap == {
  "name" : "Bob"
};
```

However, if we read `User` from a `Map` where the `id` key is the *value* null, when we transform it back to a `Map` the `id` is present and its value is null:

```dart
var userMap = {
  "id" : null
  "name" : "Bob"
};

var user = new User()..readFromMap(userMap);

user.id == null; // yup
user.name == "Bob"; // yup

var outUserMap = user.asMap();
outUserMap == {
  "id" : null
  "name" : "Bob"
};
```

A `ManagedObject<T>` like `User` makes the distinction between a value that is `null` and a value that it *doesn't have enough information for*. A property of a `ManagedObject<T>` can get set in three ways: it is read from a map, its setter is invoked or it is read from the database. In all three of these situations, not every property is available. This is no more obvious than when  creating a brand new instance:

```dart
var user = new User();
user.id == null; // yup
user.name == null; // yup

user.asMap() == {}; // yup
```

A `ManagedObject<T>` will not include keys in its `asMap()` if it doesn't have a value for them. The value may exist somewhere else - like in the database - but if it doesn't have it, it won't include it. This distinction is useful information for clients of Aqueduct applications.

So what about values that are actually `null`? A property with the value `null` will be included in `asMap()` if its been read from the database, read using `readFromMap()` or explicitly assigned with a setter. The following three user objects will all have `{"name": null}`:

```dart
var user1 = new User()
  ..id = 1
  ..name = null;

var user2 = new User()..readFromMap({
  "id": 2
  "name": null
});

var query = new Query<User>()
  ..where((u) => u.id).equalTo(3)
  ..where((u) => u.name).isNull();
var user3 = await query.fetchOne();
```

Note that an unset value that is returned from a getter will be `null`. If using an object's values to perform some calculation, it's your job to know if the value has been fetched or not. (While `ManagedObject<T>.hasValueForProperty()` checks this at runtime, that isn't a good practice.)

One last thing to note: if you wish to remove a value from a `ManagedObject<T>`s storage (and likewise, its `asMap()`), you must use `ManagedObject<T>.removePropertyFromBackingMap()`.

It is helpful to think of a `ManagedObject<T>` as a proxy to a database row that may or may not exist yet, and may have less data than actually exists in the database row.

### Transient Properties and Serialization/Deserialization

By default, transient properties and getters - those declared in the subclass of `ManagedObject<T>` - are *not* included in the `asMap()`. (Setters are obviously not included, as you can't get a value from them.) To include a transient property or getter in `asMap()`, you may mark it with `@Serialize()` metadata. Properties marked with this metadata will be included in `asMap()` if and only if they are not null. A good reason to use this feature is when you want to provide a value to the consumer of the API that is derived from persistent properties:

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize()
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

Transient properties with this annotation may also be used as inputs when reading with `readFromMap()`. For example, consider how to handle user passwords. A password is not stored in plain-text in a database, but they are sent in requests. Thus, a password could read from a request body, but it needs to be salted, hashed and stored in two columns in the database. An instance type could then define a password property, which automatically set the salt and hash of the password in the underlying persistent type:

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize()
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
var user = new User()..readFromMap(map);
var salt = user.salt; // 'somerandomstring'
var hashedPassword = user.hashedPassword; // 'somehashedstring'

var password = user.password; // Analyzer error - user.password doesn't exist!
```

A transient property can also be used only when reading or only when writing.

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize(input: true, output: false)
  String readable; // Can be readFromMap, but not emitted in asMap

  @Serialize(input: false, output: true)
  String writable; // Is emitted in asMap, but cannot be readFromMap.
}
```

Also, a separate getter and setter may exist for the same name to allow both input and output:

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize()
  void set transientValue(String s) {
    ...
  }

  @Serialize()
  String get transientValue => ...;
}
```

On a related note, persistent properties are always included in `asMap()` by default, but can be omitted by adding `Column` metadata with the `omitByDefault` option:

```dart
class _User {
  @Column(omitByDefault: true)
  String salt;

  @Column(omitByDefault: true)
  String hashedPassword;
  ...
}
```

### Serialization and Deserialization of Relationship Properties

Relationship properties - references to other `ManagedObject<T>` subclasses - can also be included in `asMap()` and read from `readFromMap()`. Relationship properties are populated when using `Query.join` - aka, a SQL JOIN.

If a relationship property has been set or read from the database, its `asMap()` will contain the nested `Map` produced by the related objects `asMap()`. For example, recall the `User` with a `job`:

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

It's important to note that "belongs to" relationships - those with `Relate` metadata - are always returned in `asMap()` when fetching an object from the database. However, the full object is not returned - only its primary key. Therefore, you will get the following result:

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

This behavior might be different than some ORMs, which may collapse the `user` into a scalar `user_id`:

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

When reading the values of a `ManagedObject<T>` with `readFromMap()`, relationship properties must also be represented as nested `Map`s or `List<Map>`. Thus:

```dart
var userMap = {
  "id": 1,
  "name": "Bob",
  "posts": [
    {"id": 1, "text": "hello"}
  ]
};

var user = new User()..readFromMap(userMap);
user.posts == new ManagedSet<Post>[
  new Post()
    ..id = 1
    ..text = "hello"
]; // yup, other Post doesn't implement == to check property equality
```
