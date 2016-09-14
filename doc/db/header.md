# Database Integration

Aqueduct is capable of integrating with a database. At a high level, Aqueduct provides the following features:

- Defining a data model
- Generating a database schema from a data model
- Executing queries to transfer data back and forth between a database
- Mapping Dart objects to database rows and back

## Modeling Your Data

In Aqueduct, persistent data is represented by *model objects*. Model objects are instances [Model] subclasses. A [Model] subclass is actually made up of two classes, a *persistent type* and an *model type*. The persistent type is a plain Dart class that defines the mapping to a database table and its columns. Here's an example:

```dart
class _User {
  @primaryKey
  int id;

  String name;
}
```

Each property in a persistent type maps to a column in a table. In this example, we are declaring that there is a table named *_User* and it has two columns, an integer primary key named `id` and a text column named `name`. You won't use instances of this class in your code, it simply provides the mapping information between your code and a database.

Instead, your application code will use instances of the model type. The model type provides the functionality for doing useful things in your application with a model object, like writing the model object to an HTTP response body. An model type must extend `Model<PersistentType>` as well as implement the interface its `PersistentType`. Here is the corresponding model type for `_User`:

```dart
class User extends Model<_User> implements _User {  
}
```

Note that by implementing the persistent type's interface, the model type has all of the properties its persistent type has. Thus, the following is valid, even though `id` and `name` were declared in the persistent type:

```dart
var user = new User()
  ..user.id = 1;
  ..user.name = "Bob";
```

This pair of classes creates a fully formed model that can be used to transfer data back and forth between a database and your application, and your application and an HTTP client.

### Persistent Types

Persistent types define the mapping between your code and a database table (and are often used to generate those tables in a database). As each property in a persistent type represents a database column, the type of the property must be storable in a database. The following list defines the simple Dart types that properties in a persistent type can be:

* int
* double
* String
* DateTime
* bool

In addition to a type and name, each property can also have [Attributes] that further specify the corresponding column. [Attributes] are added as metadata to a property. For example, the following change to the `_User` persistent type adds a `String` `email` property which must be unique across all users:

```dart
class _User {
  @primaryKey
  int id;

  String name;

  @Attributes(unique: true)
  String email;
}
```
There are eight configurable attributes available in the [Attributes] class.

* `primaryKey` - Indicates that property is the primary key of the table represented by this persistent type. Must be one per persistent type.
* `databaseType` - Uses a more specific type for the database column than can be derived from the Dart type of the property. For example, you may wish to specify that an integer property is stored in a database column that holds an 8-byte integer, instead of the default 4-byte integer.
* `nullable` - Toggles whether or not this property can contain the null value.
* `defaultValue` - A default value for this property when inserted into a database without an explicit value.
* `unique` - Toggles whether or not this property must be unique across all instances of this type.
* `indexed` - Toggles whether or not this property's database column should be indexed for faster searching.
* `omitByDefault` - Toggles whether or not this property should be fetched from the database by default. Useful for properties like hashed passwords, where you don't want to return that information when fetching an account unless you explicitly want the check the password.
* `autoincrement` - Toggles whether or not the underlying database should generate a new value from a serial generator each time a new instance is inserted into the database.

By not specifying [Attributes], the default values for each of these possible configurations is used and the database type is inferred from the type of the property.

Every persistent type must have at least one property with  [Attributes] where `primaryKey` is true. There is a convenience instance of [Attributes] for this purpose, `@primaryKey`, which is equivalent to the following:

```dart
@Attributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

By convention, persistent types begin with an underscore, but there is nothing that prevents you from changing this. Bear in mind, the name of the persistent type will be the name of the corresponding database table. You may override the name of the table by implementing a static method that returns the name of the table in a persistent type:

```dart
class _User {
  @primaryKey
  int id;

  String name;

  static String tableName() {
    return "UserTable";
  }
}
```

### Model types

Instances of model types hold data in an Aqueduct application. When data is sent as part of an HTTP request body, you may deserialize that data into a model object. That object can then be operated on and sent to the database to insert, fetch, delete or update data via a `Query`. When getting data back from a database, you will receive instances of the appropriate model type. Model objects can be used as the `body` of `Response` objects as well. The following code snippet is a pretty common usage of a model object:


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

In other words, there are three primary features of a model object: it can set its properties from a HTTP request body, it can be used to configure a `Query` and it can be used to set the body of an HTTP response.

When getting model objects from a database, each instance will represent one row. For example, consider the *_User* table and its rows, and the previous example of `_User` and `User` persistent and model types:

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

Model types may also define properties and methods on top of those it implements from its persistent type. Because these properties and methods are not part of the persistent type, they are *transient* - that is, they are not stored in the database. Any method or property defined on an model type is ignored when used in a `Query`. This is in contrast to a persistent type, where every property explicitly maps to a database column.

It is often the case that you have a method or property on the model type that makes some operation more convenient. For example, consider a model object that represented a video on a video sharing site. Each video has a persistent property that indicates when the video was uploaded. As a convenience, you'd like to be able to determine if a video instance is "recent" - that is, it has been uploaded in the last week. Adding a `isRecent` property to the persistent type doesn't make any sense, because that information can be derived from the existing upload date property. Thus, its a good use of a transient property:

```dart
class Video extends Model<_Video> implements _Video {
  bool get isRecent => return new DateTime.now().difference(uploadDate).inDays < 7;
}

class _Video {
  @primaryKey
  int id;

  DateTime uploadDate;
  ...
}
```

Note that, by default, transient properties are not serialized or deserialized.

It is important to understand that a `Model` is a effectively a wrapper around a `Map<String, dynamic>`. This `Map` is the *backing* of the `Model` object. A `Model` object's values are stored in this `Map` - when you access a property of a model object, the name of the property is transformed into a `String` key and evaluated against the backing. This is why the model type *implements* its persistent type - the actual storage for the properties declared in the persistent type are dynamically implemented by the `Model`'s backing map.

### Serialization and Deserialization

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
var map = user.asMap(); // -> {'id' : 2}

user.name = null;
map = user.asMap(); // -> {'id' : 2, 'name' : null}
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
var map = user.asMap(); // -> {'id' : 2, 'name' : 'Bob'}

user.name = null;
map = user.asMap(); // -> {'id' : 2, 'name' : null}

user.removePropertyFromBackingMap("name");
map = user.asMap(); // -> {'id' : 2}
```

### Transient Properties and Serialization/Deserialization

By default, transient properties and getters are *not* included in the `Map` produced when serializing a model object. (Setters are obviously not included, as they don't hold a value.) To include a transient property or getter during serialization, you may mark it with `@availableAsOutput` metadata. Properties marked with this metadata will be included in the serialized `Map` if and only if they are not null. A good reason to use this feature is when you want to provide a value to the consumer of the API that is derived from one or more values in persistent type of the model object:

```dart
class User extends Model<_User> implements _User {
  @availableAsOutput
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
// -> {'firstName' : 'Bob', 'lastName' : 'Boberson', 'fullName' : 'Bob Boberson'};

```

Transient properties may also be used as inputs when deserializing a `Map` into a model object by marking the property with `@availableAsInput`. For example, consider how to handle user passwords. The persistent type - a direct mapping to the database - does not have a password property for security purposes. Instead, it has a password hash and a salt. An model type could then define a password property, which automatically set the salt and hash of the password in the underlying persistent type:

```dart
class User extends Model<_User> implements _User {
  @availableAsInput
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

Transient inputs must be setters or properties. For properties that are both inputs and outputs, you may use the metadata `@availableAsInputAndOutput`. A separate getter and setter may exist for the same name to allow both input and output:

```dart
class User extends Model<_User> implements _User {
  @availableAsInput
  void set transientValue(String s) {
    ...
  }

  @availableAsOutput
  String get transientValue => ...;
}
```

### Modeling Object Relationships



## The Layers Between Aqueduct and Your Database

### A ModelContext Bridges Your Application to a Database
###

## Executing Queries

##
