---
layout: page
title: "Serialization and Deserialization"
category: db
date: 2016-06-20 10:35:56
---

While model objects are responsible for representing database rows, they are also responsible for serializing and deserializing data. Serialization converts a model object to a `Map<String, dynamic>` where each property on the model object is a key-value pair in the map. Each key is the exact name of the property. This is done by the `asMap` method.

Deserialization ingests key-value pairs from a `Map<String, dynamic>` and assigns it to the properties of a model object, where each value in the map is assigned to the property whose key matches exactly the name of the property. This is done by the `readMap` method. The following code demonstrates this behavior:

```dart
var userMap = {
    "id" : 1,
    "name" : "Bob"
};

var user = new User()..readMap(userMap);

var outUserMap = user.asMap();

// userMap == outUserMap
```

Note that serialization and deserialization are encoding agnostic. Data typically enters an application as JSON in an HTTP request body. From there, it is decoded into Dart objects like `Map`, `String` and `List`. It is only once the data is in this format that it can be deserialized into a model object. Thus, model objects don't understand what an intermediary format like JSON is. Likewise, serializing a model object produces data that can be encoded into JSON, but it does not create the JSON itself. It is up to the mechanism that is generating the HTTP response to determine the encoding format; thus, it is possible to encode model objects into another format like protocol buffers if the application calls for it.

When serializing and deserializing a model object, it is important to understand the nuances of the `null` value. As indicated earlier, a `Model` object is a glorified `Map`. When a row is fetched from a database and decoded into a `Model` object, every column/value pair is set in a `Model`'s `backingMap`. If a property is not fetched from the database, its key is not present in the backing map. (Likewise, if you create an instance of `Model`, its backing map contains no key-value pairs and only contains those that you explicitly set.) Therefore, when accessing the property of a `Model` object that was not previously set, you will get the value `null`.

However, it is also possible that a property's value is actually the `null` value and it is important to understand how this distinction impacts serialization. During serialization, if a key is not present in the backing of a `Model`, it is omitted from the serialized object. If the value of a property has been explicitly set to `null`, the key will be present and the value will be `null`. Therefore, consider the following two scenarios:

```dart
var user = new User()..id = 2;
var map = user.asMap();
map == {
  'id' : 2
};

user.name = null;
map = user.asMap();
map = {
  'id' : 2,
  'name' : null
};
```

The inverse is true when deserializing: any keys not present in the `Map` will not be set in the model's backing.

If you ever need to check whether or not a value has been set on a `Model`, you may access use the method `hasValueForProperty` or access its `backingMap` directly:

```dart
var user = new User()..id = 2;

user.hasValueForProperty("id"); // true
user.backingMap.containsKeys("id"); // true

user.backingMap.containsKeys("name"); // false
user.hasValueForProperty("name"); // false
```

Because setting the value `null` for a property doesn't "remove" that property from the backing map, you may explicitly remove a property from the backing using the method `removePropertyFromBackingMap` on `Model`.

```dart
var user = new User()
  ..id = 2
  ..name = 'Bob';
var map = user.asMap();
map == {
  'id' : 2,
  'name' : 'Bob'
};

user.name = null;
map = user.asMap();
map == {
  'id' : 2,
  'name' : null
};

user.removePropertyFromBackingMap("name");
map = user.asMap();
map == {
  'id' : 2
};
```

### Transient Properties and Serialization/Deserialization

By default, transient properties and getters are *not* included in the `Map` produced when serializing a model object. (Setters are obviously not included, as they don't hold a value.) To include a transient property or getter during serialization, you may mark it with `@transientOutputAttribute` metadata. Properties marked with this metadata will be included in the serialized `Map` if and only if they are not null. A good reason to use this feature is when you want to provide a value to the consumer of the API that is derived from one or more values in persistent type of the model object:

```dart
class User extends Model<_User> implements _User {
  @transientOutputAttribute
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

Transient properties may also be used as inputs when deserializing a `Map` into a model object by marking the property with `@transientInputAttribute`. For example, consider how to handle user passwords. The persistent type - a direct mapping to the database - does not have a password property for security purposes. Instead, it has a password hash and a salt. An instance type could then define a password property, which automatically set the salt and hash of the password in the underlying persistent type:

```dart
class User extends Model<_User> implements _User {
  @transientInputAttribute
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
var user = new User()..readMap(map); // also equivalent to user.password = 'mypassword';
var salt = user.salt; // 'somerandomstring'
var hashedPassword = user.hashedPassword; // 'somehashedstring'

var password = user.password; // error, this property does not exist!
```

Transient inputs must be setters or properties. For properties that are both inputs and outputs, you may use the metadata `@transientAttribute`. Also, a separate getter and setter may exist for the same name to allow both input and output:

```dart
class User extends Model<_User> implements _User {
  @transientInputAttribute
  void set transientValue(String s) {
    ...
  }

  @transientOutputAttribute
  String get transientValue => ...;
}
```

Transient properties marked with this metadata *are* `attributes` on an entity (like primitive properties on the persistent type, but unlike other properties on the instance type).



### Serialization and Deserialization of Relationships

A model object will serialize any relationship properties as `Map`s or a `List<Map>` if those properties are present in its `backingMap`.

'hasOne' and inverse properties are always serialized as `Map`s. Thus, the following:

```dart
var user = new User()
  ..id = 1;
  ..profile = (new Profile()..id = 2);

var userMap = user.asMap();
userMap == {
  'id' : 1,
  'profile' : {
    'id' : 2
  }
};
```

'hasMany' relationships are always serialized as a `List` of `Map`s:
```dart
var user = new User()
  ..id = 1;
  ..posts = new OrderedSet.from([
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

It is important to note the potential for cyclic object graphs. Since all relationship properties have an inverse, the two properties in that relationship are references to one another. That is, you could do something like this:

```dart
identical(user.profile.user, user);
identical(user.posts.first.user, user);
```

When fetching objects from a database, this won't happen - Aqueduct will create multiple instances of the same row when necessary to avoid this. Therefore, the previous code snippet would not be true, but the following two statements would be:

```
user.profile.user.id == user.id;

user.posts.first.user.id == user.id
```

While fetched objects will not have cyclic references, model objects you instantiate yourself can (if you mistakenly do so). While these cyclic object graphs can be used build `Query`s, they cannot be serialized. You'll get a stack overflow error. It's best to avoid creating cyclic graphs altogether. For example:

```dart

// do:
var user = ... from somewhere ...
posts.forEach((p) {
  p.user = new User()..id = user.id;
});

// do not:
var user = ... from somewhere ...
posts.forEach((p) {
  p.user = user;
});
```

Relationships may also be deserialized from a map or list of maps. Thus, the following will do what you expect:

```dart
var map = {
  'id' : 1,
  'name' : 'Bob'
  'profile' : {
    'id' : 3,
    'profilePhotoURL' : 'http://somewhereout.there'
  },
  'posts' : [
    {
      'id' : 2,
      'text' : 'Foo'
    }
  ]
};

var user = new User()
  ..readMap(map);
```
