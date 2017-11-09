# RESTController

An Aqueduct application defines the resources it manages by [adding routes to a Router](routing.md). An `RESTController` provides the implementation for all of the operations that can be taken on those resources. For example, an application might have a `users` resource and operations to create a user or get a list of users.

An operation, then, is the combination of an HTTP method and a path. For example, the HTTP request `POST /users` is an operation to create a user and `GET /users/1` is an operation to return a single user. A subclass of `RESTController` implements an instance method for each supported operation for a resource. These instance methods are called *operation methods* and must have metadata to indicate the operation it takes.

## Operation Methods

An operation method, at minimum, must *bind* the HTTP method that triggers it and return `Future<Response>`. Here's an example:

```dart
class CityController extends RESTController {
  @Bind.get()
  Future<Response> getAllCities() async {
    return new Response.ok(["Atlanta", "Madison", "Mountain View"]);
  }
}
```

This controller defines an operation method for `GET` requests. Adding an instance of this controller to the channel for the route `/cities` binds the operation `GET /cities` to `getAllCities`.

```dart
router
  .route("/cities")
  .generate(() => new CityController());
```

!!! tip
    `RESTController`s are added to the channel with `generate`. This creates a new instance of `CityController` for each request, which gives us the ability to store values in the properties of the controller that are related to the request being handled.

An `RESTController` can implement operations for a collection of resources and for individual resources in that collection. For example, it makes sense that a `CityController` implement operation methods for both `GET /cities` and `GET /cities/1` because these operations likely share logic and dependencies. Here's an example:

```dart
class CityController extends RESTController {
  final cities = ["Atlanta", "Madison", "Mountain View"];

  @Bind.get()
  Future<Response> getAllCities() async {
    return new Response.ok(cities);
  }

  @Bind.get()
  Future<Response> getOneCity(@Bind.path("name") String cityName) async {
    var city = cities.firstWhere((c) => c.name == cityName, orElse: () => null);
    if (city == null) {
      return new Response.notFound();
    }
    return new Response.ok(city);
  }
}
```

In the above, there are two operation methods for `GET` requests but the arguments are different. The second method - `getOneCity` - binds its `cityName` argument with `Bind.path("name")`. This gives us the following behavior:

- If the incoming request has a path variable named `name`, `getOneCity` will be invoked.
- If the incoming request has no path variables, `getAllCities` will be invoked.

Recall that path variables are created when setting up routes. The following channel construction would route requests that are both `/cities` and `/cities/:name` to an instance of `CityController`:

```dart
router
  .route("/cities/[:name]")
  .generate(() => new CityController());
```

Take notice that the `name` path variable in the route above is *optional* - otherwise this route would not match `/cities`. Also take notice that the argument to `Bind.path` exactly matches the name of the path variable in the route - this is required. If an `RESTController` doesn't have an operation method for a given operation, a 405 Method Not Allowed response is sent and no operation method is invoked.

The type of an argument that is bound to a path variable may be a `String` or any type that implements a `parse` method (e.g., `int`, `double`, `DateTime`). If the path variable cannot be parsed into the bound variable's type, a 404 Not Found response is sent and no operation method is invoked.

Any number of path variables can exist in a route and have operation methods in the corresponding `RESTController`. However, it is considered good practice to break sub-resources into their own controller. For example, the following is preferred:

```dart
router
  .route("/cities/[:name]")
  .generate(() => new CityController());

router  
  .route("/cities/:name/attractions/[:id]")
  .generate(() => new CityAttractionController());
```

By contrast, the route `/cities/[:name/[attractions/[:id]]]`, while valid, makes controller logic much more unwieldy.

!!! note
    There are bindings for other HTTP methods, e.g. `Bind.post()`. Non-standard methods can be bound with `Bind.method("METHOD_NAME")`.

## Other Types of Binding

The values of query parameters, headers and the request body may also be bound to arguments of an operation method. For example, the following operation method for `GET /cities` requires an `X-API-Key` header:

```dart
class CityController extends RESTController {
  @Bind.get()
  Future<Response> getAllCities(@Bind.header("x-api-key") String apiKey) async {
    if (!isValid(apiKey)) {
      return new Response.unauthorized();
    }

    return new Response.ok(["Atlanta", "Madison", "Mountain View"]);
  }
}
```

If the header `X-API-Key` exists in the request, its value will be available in the variable `apiKey` when `getAllCities` is invoked. If this header did not exist in the request, a 400 Bad Request response would be sent and `getAllCities` would not be invoked.

However, `apiKey` can be made optional. To make an binding variable optional, move it to the optional parameters of the method:

```dart
@Bind.get()
Future<Response> getAllCities({@Bind.header("x-api-key") String apiKey}) async {
  if (apiKey == null) {
    // No X-API-Key in request
    ...
  }

  ...
}
```

When a request doesn't contain a bound element, its bound variable is null. In this example, `apiKey` will null for a request without the `X-API-Key` header. You may provide a default value for optional bindings using standard Dart syntax.

!!! note "Optional Bindings"
    Only header, query and body bindings can be optional. `Bind.path` properties are necessary for choosing which operation method to invoke and therefore must be required. Header, query and body bindings have no impact on which operation method is selected. Conceptually, you can view `RESTController` behavior as two steps: an operation method is selected by the method/path of the request, and then values are read from the request and passed as arguments into the method.

The next sections go over the details of header, body and query bindings.

### Query Parameter Binding

Query string parameters may be bound with `Bind.query`. The variable bound to a query parameter must be a `String`, `bool`, a type that implements `parse` or a `List` of the aforementioned. For example, the following operation method will bind the query string parameters `limit` and `offset`:

```dart
@Bind.get()
Future<Response> getAllCities({
  @Bind.query("limit") int numberOfCities: 100,
  @Bind.query("offset") int offset: 0}) async {
    final cities = ["Atlanta", "Madison", "Mountain View"];
    return new Response.ok(cities.sublist(offset, offset + limit));
}
```

Thus, if the request URI were `/cities?limit=2&offset=1`, the values of `numberOfCities` and `offset` are 2 and 1, respectively. The argument to `Bind.query` is case-sensitive since URI query strings are case-sensitive.

Boolean values are used when the expected query parameter has no value. For example, if a binding were `@Bind.query("include_foreign") bool includeForeignCities`, the bound value would be true for the URI `/cities?include_foreign`.

A query parameter can appear multiple times in a query string. If the bound value type is not a `List` and the query key appears more than once, a 400 Bad Request is sent. If it is a `List` and one or more query keys exist, each of their values is added available in the bound list.

It is important to note that if a query string is in the body and `Content-Type` is `x-www-form-urlencoded`, you may still bind query parameters using `Bind.query`.

### Header Binding

Headers are bound in the same way as query parameters, using `Bind.header` metadata. Unlike `Bind.query`, `Bind.header`s are compared case-insensitively. Here's an example of a operation method that takes an optional `X-Timestamp` header:

```dart
@Bind.get()
Future<Response> getThings(
  {@Bind.header("x-timestamp") DateTime timestamp}) async {
    ...
}
```

### Binding HTTP Request Bodies

You may also bind an HTTP request body to an object with `@Bind.body` metadata, as long as the bound method supports request bodies:

```dart
@Bind.post()
Future<Response> createUser(@Bind.body() User user) async {
  var query = new Query<User>()
    ..values = user;
  var insertedUser = await query.insert();
  return new Response.ok(insertedUser);
}
```

The type of the bound variable must implement `HTTPSerializable`. This interface requires that the methods `readFromMap()` and `asMap()` be implemented:

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

class PersonController extends RESTController {
  @Bind.post()
  Future<Response> createPerson(@Bind.body() Person p) {
    // p.name and p.email are read from body when body is
    // {"name": "...", "email": "..."}
  }
}
```

You may also bind a `List<HTTPSerializable>`:

```dart
class PersonController extends RESTController {
  @Bind.post()
  Future<Response> createPerson(@Bind.body() List<Person> people) {
    // When body is [{"name": "...", "email": "..."}]
  }
}
```

The request body is decoded based on its content type prior to binding it to an `HTTPSerializable`.

Note that if the request's `Content-Type` is `x-www-form-urlencoded` and the query string is in the body, it must be bound with `Bind.query` and not `Bind.body`.

### Property Binding

The properties of an `RESTController`s may also have `Bind.query` and `Bind.header` metadata. This binds values from the request to the `RESTController` instance itself, making them accessible from *all* operation methods.

```dart
class ThingController extends RESTController {
  @requiredHTTPParameter
  @Bind.header("x-timestamp")
  DateTime timestamp;

  @Bind.query("limit")
  int limit;

  @Bind.get()
  Future<Response> getThings() async {
      // can use both limit and timestamp
  }

  @Bind.get()
  Future<Response> getThing(@Bind.path("id") int id) async {
      // can use both limit and timestamp
  }
}
```

In the above, both `timestamp` and `limit` are bound prior to `getThing` and `getThings` being invoked. By default, a bound property is optional but can have additional `requiredHTTPParameter` metadata. If required, any request without the required property fails with a 400 Bad Request status code and none of the operation methods are invoked.


## Other RESTController Behavior

Besides binding, `RESTController`s have some other behavior that is important to understand.

### Request and Response Bodies

An `RESTController` can limit the content type of HTTP request bodies it accepts. By default, an `RESTController` will accept both `application/json` and `application/x-www-form-urlencoded` request bodies for its `POST` and `PUT` methods. This can be modified by setting the `acceptedContentTypes` property in the constructor.

```dart
class UserController extends RESTController {
  UserController() {
    acceptedContentTypes = [ContentType.JSON, ContentType.XML];
  }
}
```

If a request is made with a content type other than the accepted content types, the controller automatically responds with a 415 Unsupported Media Type response.

The body of an HTTP request is decoded if the content type is accepted and there exists a operation method to handle the request. This means two things. First, the body is not decoded if the request is going to be discarded because no operation method was found.

Second, methods on `HTTPRequestBody` have two flavors: those that return the contents as a `Future` or those that return the already decoded body. Operation methods can access the already decoded body without awaiting on the `Future`-flavored variants of `HTTPRequestBody`:

```dart
@Bind.post()
Future<Response> createThing() async {
  // do this:
  var bodyMap = request.body.asMap();

  // no need to do this:
  var bodyMap = await request.body.decodeAsMap();

  return ...;
}
```

An `RESTController` can also have a default content type for its *response* bodies. By default, this is `application/json` - any response body returned as JSON. This default can be changed by changing `responseContentType` in the constructor:

```dart
class UserController extends RESTController {
  UserController() {
    responseContentType = ContentType.XML;
  }
}
```

The `responseContentType` is the *default* response content type. An individual `Response` may set its own `contentType`, which takes precedence over the `responseContentType`. For example, the following controller returns JSON by default, but if the request specifically asks for XML, that's what it will return:

```dart
class UserController extends RESTController {
  UserController() {
    responseContentType = ContentType.JSON;
  }

  @Bind.get()
  Future<Response> getUserByID(@Bind.path("id") int id) async {
    var response = new Response.ok(...);

    if (request.headers.value(Bind.headers.ACCEPT).startsWith("application/xml")) {
      response.contentType = ContentType.XML;
    }

    return response;
  }
}
```

### More Specialized RESTControllers

Because many `RESTController` subclasses will execute [queries](../db/executing_queries.md), there are helpful `RESTController` subclasses for reducing boilerplate code.

A `QueryController<T>` builds a `Query<T>` based on the incoming request. If the request has a body, this `Query<T>`'s `values` property is read from that body. If the request has a path variable, the `Query<T>` assigns a matcher to the primary key value of its `where`. For example, in a normal `RESTController` that responds to a PUT request, you might write the following:

```dart
@Bind.put()
Future<Response> updateUser(@Bind.path("id") int id, @Bind.body() User user) async {
  var query = new Query<User>()
    ..where.id = whereEqualTo(id)
    ..values = user;

  return new Response.ok(await query.updateOne());
}
```

A `QueryController<T>` builds this query before a operation method is invoked, storing it in the inherited `query` property. A `ManagedObject<T>` subclass is the type argument to `QueryController<T>`.

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

This also means that an `RESTController` instance cannot be reused to handle multiple requests; if it awaited on an operation, a new request could be assigned to the `request` property. Therefore, all `RESTController`s must be added to a request processing pipeline with `generate`. If you add a controller with `pipe`, an exception will be thrown immediately at startup.
