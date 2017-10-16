# HTTPController

Most Aqueduct code is written in subclasses of `HTTPController`. Instances of this class receive requests for a particular resource. For example, an `HTTPController` subclass named `UserController` might handle requests to create, update, delete, read and list users. `HTTPController` is subclassed to implement an instance method for each one of these operations.

For example, a `POST /users` would trigger a `createUser` method, whereas a `GET /users/1` would trigger a `getUserByID` method. The names of these methods are up to you; the method that gets called is determined by metadata on the method and its parameters.

### Responder Methods and Parameter Binding

An `HTTPController` method that responds to a request is called a *responder method*. A responder method must return a `Future<Response>` and have `Bind.method` metadata. Here's an example:

```dart
class UserController extends HTTPController {
  @Bind.method("get")
  Future<Response> getAllUsers() async {
    return new Response.ok(await getUsersFromDatabase());
  }
}
```

When a `GET` request is sent to an instance of `UserController`, the method `getAllUsers` is invoked and the `Response` it returns is sent to the HTTP client. If a request is sent to an `HTTPController` and there isn't a responder method bound to its HTTP method, a 405 response is sent and no method is invoked.

Each responder method can *bind* values from the HTTP request to its arguments. The following responder method binds the value from the path variable `id`:

```dart
@Bind.method("get")
Future<Response> getOneUser(@Bind.path("id") int id) async {
  return new Response.ok(await getAUserFromDatabaseByID(id));
}
```

When a [route contains a path variable](routing.md) (like `/users/:id`), the value of that path variable will be available in this argument. It is often the case that a path variable is an optional part of a route (like `/users/[:id]`). Thus, the request `/users` and `/users/:id` get sent to the same controller. There must be a responder method for both variants. For example, the following controller may respond to both `GET /users` and `GET /users/1`:

```dart
class UserController extends HTTPController {
  @Bind.method("get")
  Future<Response> getAllUsers() async {
    // invoked with path is /users
  }

  @Bind.method("get")
  Future<Response> getOneUser(@Bind.path("id") int id) async {
    // invoked with path is /users/:id
  }
}
```

The argument to `Bind.path` is the name of the path variable as it is declared in the route. For example, if the route is `/thing/:abcdef`, the argument must be `"abcdef"`.

The variable that `Bind.path` is bound to can be named whatever you want - you don't have to name it the same as the path variable.

The *type* of the bound variable can be a `String` or any type that has a `parse` method (like `int`, `double`, `HttpDate` and `DateTime`). If the bound variable's type is not `String` or a type that implements `parse`, a 500 Server Error is returned.

If the bound path variable's type does implement `parse`, but the value from the request is in an invalid format, a 404 Not Found response is returned.

Query string parameters and header values may also be bound to responder methods with `Bind.query` and `Bind.header` metadata. (Note that a failed parse for query or header binding return a 400 Bad Request response.) The following responder method will bind the query string parameters `limit` and `offset` to `numberOfThings` and `offset`:

```dart
@Bind.method("get")
Future<Response> getThing(
  @Bind.query("limit") int numberOfThings,
  @Bind.query("offset") int offset) async {
    var things = await getThingsBetween(offset, offset + numberOfThings);
    return new Response.ok(things);
}
```

For example, if the request was `/?limit=10&offset=0`, the values of `numberOfThings` and `offset` are 10 and 1. In this above method, both `limit` and `offset` are *required*. If one or both are values are missing from the query string in a request, the responder method is not called and a 400 Bad Request response is sent.

Query parameters can be made optional by moving them to the optional part of the method signature. Thus, the following method still requires `limit`, but if `offset` is omitted, its value defaults to 0:

```dart
@Bind.method("get")
Future<Response> getThing(
  @Bind.query("limit") int numberOfThings,
  {@Bind.query("offset") int offset: 0}) async {
    var things = await getThingsBetween(offset, offset + numberOfThings);
    return new Response.ok(things);
}
```

The argument to `Bind.query` is case-sensitive.

Headers are bound in the same way using `Bind.header` metadata. Unlike `Bind.query`, `Bind.header`s are compared case-insensitively. Here's an example of a responder method that takes an optional `X-Timestamp` header:

```dart
@Bind.method("get")
Future<Response> getThings(
  {@Bind.header("x-timestamp") DateTime timestamp}) async {
    ...
}
```

The properties of an `HTTPController`s may also have `Bind.query` and `Bind.header` metadata. This binds values from the request to the `HTTPController` instance itself, making them accessible from *all* responder methods.

```dart
class ThingController extends HTTPController {
  @requiredHTTPParameter
  @Bind.header("x-timestamp")
  DateTime timestamp;

  @Bind.query("limit")
  int limit;

  @Bind.method("get")
  Future<Response> getThings() async {
      // can use both limit and timestamp
  }

  @Bind.method("get")
  Future<Response> getThing(@Bind.path("id") int id) async {
      // can use both limit and timestamp
  }
}
```

In the above, both `timestamp` and `limit` are bound prior to `getThing` and `getThings` being invoked. By default, a bound property is optional but can have additional `requiredHTTPParameter` metadata. If required, any request without the required property fails with a 400 Bad Request status code and none of the responder methods are invoked.

Aqueduct treats `POST` and `PUT` requests with `application/x-www-form-urlencoded` content type as query strings, so the body of the request can be bound to `Bind.query` parameters.

Query strings can have repeating keys, i.e. `/?x=1&x=2`. You may also bind a query parameter to a `List`:

```dart
@Bind.method("get")
Future<Response> getThing(@Bind.query("x") List<String> xs) async {
  // xs = ["1", "2"]
}
```

Query strings may also have no value, i.e. `/?flag`. You may bind a query parameter to a boolean that will be true if the bound key is present in the query string:

```dart
@Bind.method("get")
Future<Response> getThing(@Bind.query("flag") bool flag) async {
  // xs = true
}
```

### Binding HTTP Request Bodies

You may also bind an HTTP request body to an object with `@Bind.body` metadata:

```dart
@Bind.method("post")
Future<Response> createUser(@Bind.body() User user) async {
  var query = new Query<User>()
    ..values = user;
  var insertedUser = await query.insert();
  return new Response.ok(insertedUser);
}
```

Body binding is available for both properties and responder method parameters, just like query and header bindings.

An type must implement `HTTPSerializable` to be bound to a request body. This interface requires that the method `readFromMap` be implemented:

```dart
class Person implements HTTPSerializable {
  String name;
  String email;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {
    name = requestBody["name"];
    email = requestBody["email"];
  }

  @override
  Map<String, dynamic> asMap() {
    return {
      "name": name,
      "email": email
    };
  }
}

class PersonController extends HTTPController {
  @Bind.method("post")
  Future<Response> createPerson(@Bind.body() Person p) {
    // p.name and p.email are read from body when body is {"name": "...", "email": "..."}
  }
}
```

You may also bind a `List<HTTPSerializable>`:

```dart
class PersonController extends HTTPController {
  @Bind.method("post")
  Future<Response> createPerson(@Bind.body() List<Person> people) {
    // When body is [{"name": "...", "email": "..."}]
  }
}
```

The request body is decoded based on its content type prior to binding it to an `HTTPSerializable`. Thus, for data like `application/json`, the bound body object is read from a `Map<String, dynamic>`.

### Request and Response Bodies

An `HTTPController` can limit the content type of HTTP request bodies it accepts. By default, an `HTTPController` will accept both `application/json` and `application/x-www-form-urlencoded` request bodies for its `POST` and `PUT` methods. This can be modified by setting the `acceptedContentTypes` property in the constructor.

```dart
class UserController extends HTTPController {
  UserController() {
    acceptedContentTypes = [ContentType.JSON, ContentType.XML];
  }
}
```

If a request is made with a content type other than the accepted content types, the controller automatically responds with a 415 Unsupported Media Type response.

The body of an HTTP request is decoded if the content type is accepted and there exists a responder method to handle the request. This means two things. First, the body is not decoded if the request is going to be discarded because no responder method was found.

Second, methods on `HTTPRequestBody` have two flavors: those that return the contents as a `Future` or those that return the already decoded body. Responder methods can access the already decoded body without awaiting on the `Future`-flavored variants of `HTTPRequestBody`:

```dart
@Bind.method("post")
Future<Response> createThing() async {
  // do this:
  var bodyMap = request.body.asMap();

  // no need to do this:
  var bodyMap = await request.body.decodeAsMap();

  return ...;
}
```

An `HTTPController` can also have a default content type for its *response* bodies. By default, this is `application/json` - any response body returned as JSON. This default can be changed by changing `responseContentType` in the constructor:

```dart
class UserController extends HTTPController {
  UserController() {
    responseContentType = ContentType.XML;
  }
}
```

The `responseContentType` is the *default* response content type. An individual `Response` may set its own `contentType`, which takes precedence over the `responseContentType`. For example, the following controller returns JSON by default, but if the request specifically asks for XML, that's what it will return:

```dart
class UserController extends HTTPController {
  UserController() {
    responseContentType = ContentType.JSON;
  }

  @Bind.method("get")
  Future<Response> getUserByID(@Bind.path("id") int id) async {
    var response = new Response.ok(...);

    if (request.headers.value(Bind.headers.ACCEPT).startsWith("application/xml")) {
      response.contentType = ContentType.XML;
    }

    return response;
  }
}
```

### More Specialized HTTPControllers

Because many `HTTPController` subclasses will execute [queries](../db/executing_queries.md), there are helpful `HTTPController` subclasses for reducing boilerplate code.

A `QueryController<T>` builds a `Query<T>` based on the incoming request. If the request has a body, this `Query<T>`'s `values` property is read from that body. If the request has a path variable, the `Query<T>` assigns a matcher to the primary key value of its `where`. For example, in a normal `HTTPController` that responds to a PUT request, you might write the following:

```dart
@Bind.method("put")
Future<Response> updateUser(@Bind.path("id") int id) async {
  var query = new Query<User>()
    ..where.id = whereEqualTo(id)
    ..values = (new User()..readFromMap(request.body.asMap());

  return new Response.ok(await query.updateOne());
}
```

A `QueryController<T>` builds this query before a responder method is invoked, storing it in the inherited `query` property. A `ManagedObject<T>` subclass is the type argument to `QueryController<T>`.

```dart
class UserController extends QueryController<User> {
  Future<Response> updateUser(@Bind.path("id") int id) async {
    // query already exists and is identical to the snippet above
    var result = await query.updateOne();
    return new Response.ok(result);
  }
}
```

A `ManagedObjectController<T>` is significantly more powerful; you don't even need to subclass it. It does all the things a CRUD endpoint does without any code. Here's an example usage:

```dart
router
  .route("/users/[:id]")
  .generate(() => new ManagedObjectController<User>());
```

This controller has the following behavior:

Request|Action
--|----
POST /users|Inserts a user into the database with values from the request body
GET /users|Fetches all users in the database
GET /users/:id|Fetches a single user by id
DELETE /users/:id|Deletes a single user by id
PUT /users/:id|Updated a single user by id, using values from the request body

The objects returned from getting the collection - e.g, `GET /users` - can be modified with query parameters. For example, the following request will return the users sorted by their name in ascending order:

```
GET /users?sortBy=name,asc
```

The results can be paged (see [Paging in Advanced Queries](../db/advanced_queries.md)) with query parameters `offset`, `count`, `pageBy`, `pageAfter` and `pagePrior`.

A `ManagedObjectController<T>` can also be subclassed. A subclass allows for callbacks to be overridden to adjust the query before execution, or the results before sending the respond. Each operation - fetch, update, delete, etc. - has a pair of methods to do this. For example, the following subclass alters the query and results before any update via `PUT`:

```dart
class UserController extends ManagedObjectController<User> {
  Future<Query<User>> willUpdateObjectWithQuery(
      Query<User> query) async {
    query.values.lastUpdatedAt = new DateTime.now().toUtc();
    return query;
  }

  Future<Response> didUpdateObject(User object) async {
    object.removePropertyFromBackingMap("private");
    return new Response.ok(object);
  }
}
```

See also [validations](../db/validations.md), which are powerful when combined with `ManagedObjectController<T>`.

### Accessing the Request

Any value from the request itself can be accessed through the `request` property of a controller.

This also means that an `HTTPController` instance cannot be reused to handle multiple requests; if it awaited on an operation, a new request could be assigned to the `request` property. Therefore, all `HTTPController`s must be added to a request processing pipeline with `generate`. If you add a controller with `pipe`, an exception will be thrown immediately at startup.
