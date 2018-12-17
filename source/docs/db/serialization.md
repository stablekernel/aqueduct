# ManagedObject Serialization and Deserialization

In this guide, you will learn how `ManagedObject<T>`s are read from HTTP request bodies and written to HTTP response bodies.

## Basic Behavior

A `ManagedObject<T>` can be converted to and from `Map<String, dynamic>` objects (which can be encoded and decoded into request or response body using JSON or some other data format). To decode a `ManagedObject` into a `Map`, use the instance method `readFromMap`:

```dart
final object = MyManagedObject();
object.readFromMap({
  "key": "value"
});

// object.key == "value"
```

When decoding, the value for each key in the map is assigned to the managed object property of the same name. If a key exists in the map and the managed object does not have a property of the same name, a `ValidationException` will be thrown (this sends a 400 Bad Request response if uncaught). If a value is not the correct type for the property it is being assigned to, the same exception (with a different error message) is thrown.

To encode a map into a managed object is converted, use the instance method `asMap`:

```dart
final object = MyManagedObject();
final map = object.asMap();
```

The resulting map will contain the values set on the managed object for keys that match the name of the property.

The values of a `Map` equivalent of a managed object are always primitive values that can be encoded as JSON, sent across an isolate, etc. The following shows a table of the

| Dart Type | Serialized Type |
|-----------|---------------|
| `int` | number (`int`) |
| `double` | number (`double`) |
| `String` | string (`String`) |
| `DateTime` | ISO 8601 Timestamp (`String`) |
| `bool` | boolean (`bool`) |
| `Document` | map or list (`Map<String, dynamic>` or `List<dynamic>`) |
| Any `enum` | string (`String`) |
| Belongs-To or Has-One Relationship | map (`Map<String, dynamic>`) |
| Has-Many Relationship | list of maps (`List<Map<String, dynamic>>`) |

Both `asMap` and `readFromMap` are inherited methods from `Serializable`. As a `Serializable`, a managed object can be [bound to a request body in an `ResourceController` operation method](../http/resource_controller.md) and [encoded as a response body object](../http/request_and_response.md). For example:

```dart
class UserController extends ResourceController {
  @Operation.post()
  Future<Response> createUser(@Bind.body() User user) async {
    var query = Query<User>(context)
      ..values = user;

    final newUser = await query.insert();

    return Response.ok(newUser);
  }
}
```

Also, recall that `List<Serializable>` can also be bound to a request body or encoded as a response body, and therefore so can `List<ManagedObject>`.

!!! note "Autoincrementing Properties"
      Properties that are autoincrementing will never be read from a map from `readFromMap`.

## Behavior of Null Values

A property of a managed object can be null for two reasons: the value is actually null, or the value is not available. For example, when you create a new instance of a managed object, none of its values are available (the object is empty). When encoding an object into a map, only the available values are included and the keys for any unavailable properties are omitted:

```dart
final myObject = MyManagedObject(); // empty object
myObject.asMap() == {}; // true

myObject.id = 1;
myObject.asMap() == {
  "id": 1
}; // true
```

A value in managed object's `asMap` will only be null if the property value truly is null:

```dart
myObject.id = null;
myObject.asMap() == {
  "id": null
}; // true
```

A property value becomes available when it is set through an accessor of the object, when invoking `readFromMap` with a map that contains the associated key, or when using a fetch `Query` that fetches the associated column.

## Behavior of Transient Properties

By default, transient properties - those declared in the managed object subclass, not the table definition - are *not* included in an object's `asMap()`. The `Serialize` annotation allows a transient property to be included in this map.

```dart
class Employee extends ManagedObject<_Employee> implements _Employee {
  int a; // NOT included in asMap, NOT read in readFromMap

  @Serialize()
  int b; // included in asMap, read in readFromMap

  @Serialize(input: true, output: false)
  int c; // NOT included in asMap, read in readFromMap

  @Serialize(input: false, output: true)
  int d; // included in asMap, NOT read in readFromMap
}

class _Employee {
  @primaryKey
  int id;
}
```

A separate getter and setter may exist instead of a property. Getters with the `Serialize` annotation will be written in `asMap` and setters with the annotation will be read in `readFromMap`.

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize()
  set transientValue(String s) {
    ...
  }

  @Serialize()
  String get transientValue => ...;
}
```

A transient property's key will not be present in `asMap()` if its value is null.

## Behavior of Relationship Properties

When a managed object is encoded, relationship properties are represented as maps (for belongs-to or has-one relationships) or a list of maps (for has-many relationships). The same rules for property availability apply to relationship properties. The following shows an example map that mirrors a managed object with aptly named relationship properties:

```dart
{
  "id": 1,
  "belongsTo": {
    "id": 1
  },
  "hasOne": {
    "id": 2,
    "name": "Fred"
  },
  "hasMany": [
    {"id": 3, "name": "Bob"},
    {"id": 4, "name": "Joe"},
  ]
}
```

A belongs-to relationship is *always* a map. This is important for client applications that will often create or update an object's belongs-to relationships. For example, a client wishing to create a child named Timmy with the parent that has `id == 1` would send the following JSON:

```dart
{
  "name": "Timmy",
  "parent": {
    "id": 1
  }
}
```

This is different from some frameworks that would flatten this structure, e.g.:

```dart
{
  "name": "Timmy",
  "parent_id": 1
}
```
