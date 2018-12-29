# ManagedObject Serialization and Deserialization

In this guide, you will learn how `ManagedObject<T>`s are read from HTTP request bodies and written to HTTP response bodies.

## Basic Conversion

A `ManagedObject<T>` can be converted to and from `Map<String, dynamic>` objects. Each key is the name of a property in the object. To decode a `ManagedObject` into a `Map`, call its `read` method:

```dart
final object = MyManagedObject();
object.read({
  "key": "value"
});

// object.key == "value"
```

Validation exceptions (status code: 400) are thrown is the input data is invalid: if a key doesn't have a corresponding property, the type of a value does not match the expected type or some constraint of the managed object is violated.

Filters can be applied to keys of the object being read. Filters can ignore keys, require keys or throw an exception if a key is present. Here is an example, where the read will throw an exception because 'id' is required but not provided:

```dart
object.read({
  "key": "value"
}, require: ["id"]);
```

!!! tip "ManagedObjects inherit Serializable"
    The `read` method and its filters are inherited from `Serializable` and are discussed in more detail [here](../http/request_and_response.md). Managed objects, like serializables, can be bound to operation method parameters.

Managed objects have a list of default keys that can be used as a base filter set:

```dart
object.read({}, require: object.entity.defaultProperties);
```

To serialize a managed object into a map, use the instance method `asMap`:

```dart
final object = MyManagedObject();
Map<String, dynamic> map = object.asMap();
```

If a property has not been set on the object, it will not be written to the map.

The values of a `Map` equivalent of a managed object are always primitive values that can be encoded as JSON, sent across an isolate, etc. The following shows a table of the serialization format:

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

A property value becomes available when it is set through an accessor, when using `read`, or when returning objects from a query.

## Behavior of Transient Properties

By default, transient properties - those declared in the managed object subclass, not the table definition - are *not* included in an object's `asMap()`. The `Serialize` annotation allows a transient property to be included in this map.

```dart
class Employee extends ManagedObject<_Employee> implements _Employee {
  int a; // NOT included in asMap, NOT read in read

  @Serialize()
  int b; // included in asMap, read in read

  @Serialize(input: true, output: false)
  int c; // NOT included in asMap, read in read

  @Serialize(input: false, output: true)
  int d; // included in asMap, NOT read in read
}

class _Employee {
  @primaryKey
  int id;
}
```

A separate getter and setter may exist instead of a property. With this annotation, getters are added to `asMap` and setters will be input for `read`.

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
