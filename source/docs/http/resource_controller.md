# ResourceController

A `ResourceController` is a [controller](controller.md) that provide conveniences for implementing endpoint controllers. A `ResourceController` must be subclassed, and in that subclass, you write a method for each operation on that type of resource. For example, a `UserController` might handle the following operations:

- creating a new user (`POST /users`)
- getting all users (`GET /users`)
- getting an individual user (`GET /users/:id`)
- updating an individual user (`PUT /users/:id`)
- deleting an individual user (`DELETE /users/:id`)

These methods that are invoked for an operation are called *operation methods*.

## Operation Methods

An operation method is an instance method of a `ResourceController` subclass that has an `@Operation` annotation. It must return an instance of `Future<Response>`. Here's an example:

```dart
class CityController extends ResourceController {
  @Operation.get()
  Future<Response> getAllCities() async {
    return new Response.ok(["Atlanta", "Madison", "Mountain View"]);
  }
}
```

The above operation method will be invoked when `CityController` handles `GET` requests without path variables. To handle operation methods with path variables, the name of the path variable is added to the `@Operation` annotation:

```dart
class CityController extends ResourceController {
  @Operation.get()
  Future<Response> getAllCities() async {
    return new Response.ok(["Atlanta", "Madison", "Mountain View"]);
  }

  @Operation.get('name')
  Future<Response> getCityByName() async {
    final id = request.path.variables['name'];
    return new Response.ok(fetchCityWithName(name));
  }
}
```

!!! note "Path Variables"
    This controller would be linked to the route specification `/cities/[:name]`, so that it can handle both of these operations. Read more about path variables in [Routing](routing.md).

The named constructor of `Operation` tells us which HTTP method the operation method handles. The following named constructors exist:

- `Operation.post()`
- `Operation.get()`
- `Operation.put()`
- `Operation.delete()`

The canonical `Operation()` constructor takes the HTTP method as its first argument for non-standard operations, e.g.:

```dart
@Operation('PATCH', 'id')
Future<Response> patchObjectWithID() async => ...;
```

All `Operation` constructors take a variable list of path variables. There can be multiple path variables for an operation. An operation method will only be invoked if all of its path variables are present in the request path. There can be multiple operation methods for a given HTTP method, as long as each expects a different set of path variables.

Here's an example of an operation that requires two path variables:

```dart
@Operation.get('userID', 'itemID')
Future<Response> getUserItem() async {
  final userID = request.path.variables['userID'];
  final itemID = request.path.variables['itemID'];
  return new Response.ok(...);
}
```

If no operation method exists for a request, a 405 Method Not Allowed response is automatically sent and no operation method is invoked.

## Routing to a ResourceController

A `ResourceController` subclass must be preceded by a `Router` in the application channel. The `Router` will parse path variables so that the controller can use them to determine which operation method should be invoked. A typical route to a `ResourceController` contains an optional identifying path variable:

```dart
router
  .route("/cities/[:name]")
  .link(() => new CityController());
```

This route would allow `CityController` to implement operation methods for all HTTP methods with both no path variables and the 'name' path variable.

It is considered good practice to break sub-resources into their own controller. For example, the following is preferred:

```dart
router
  .route("/cities/[:name]")
  .link(() => new CityController());

router
  .route("/cities/:name/attractions/[:id]")
  .link(() => new CityAttractionController());
```

By contrast, the route `/cities/[:name/[attractions/[:id]]]`, while valid, makes controller logic much more unwieldy.

## Request Bindings

Operation methods may *bind* properties of an HTTP request to its parameters. When the operation method is invoked, the value of that property is passed as an argument to the operation method. For example, the following binds the header named 'X-API-Key' to the argument `apiKey`:

```dart
@Operation.get('name')
Future<Response> getCityByName(@Bind.header('x-api-key') String apiKey) async {
  if (!isValid(apiKey)) {
    return new Response.unauthorized();
  }

  return new Response.ok(...);
}
```

The following table shows the possible types of bindings:

Property | Binding
---|---
Path Variable | `@Bind.path(pathVariableName)`
URL Query Parameter | `@Bind.query(queryParameterName)`
Header | `@Bind.header(headerName)`
Request Body | `@Bind.body()`

You may bind any number of HTTP request properties to a single operation method.

### Optional Bindings

Bindings can be made optional. If a binding is optional, the operation method will still be called even if the bound property isn't in a request. To make a binding optional, move it to the optional parameters of an operation method:

```dart
@Operation.get()
Future<Response> getAllCities({@Bind.header('x-api-key') String apiKey}) async {
  if (apiKey == null) {
    // No X-API-Key in request
    ...
  }
  ...
}
```

A bound parameter will be null if not in the request. Like any other Dart optional parameter, you can provide a default value:

```dart
@Operation.get()
Future<Response> getAllCities({@Bind.header("x-api-key") String apiKey: "public"}) async {
  ...
}
```

### Automatically Parsing Bindings

Query, header and path bindings can automatically be parsed into other types, such as `int` or `DateTime`. Simply declare the bound parameter's type to the desired type:

```dart
Future<Response> getCityByID(@Bind.query('id') int cityID)
```

The type of a bound parameter may be `String` or any type that implements `parse` (e.g., `int`, `DateTime`). Query parameters may also be bound to `bool` parameters; a boolean query parameter will be true if the query parameter has no value (e.g. `/path?boolean`).

If parsing fails for any reason, an error response is sent and the operation method is not called. For example, the above example binds `int cityID` - if the path variable 'id' can't be parsed into an `int`, a 404 Not Found response is sent. If a query parameter or header value cannot be parsed, a 400 Bad Request response is sent.

You may also bind `List<T>` parameters to headers and query parameters, where `T` must meet the same criteria as above. Query parameters and headers may appear more than once in a request. For example, the value of `ids` is `[1, 2]` if the request URL ends with `/path?id=1&id=2` and the operation method looks like this:

```dart
Future<Response> getCitiesByIDs(@Bind.query('id') List<int> ids)
```

Note that if a parameter is *not* bound to a list and there are multiple occurrences of that property in the request, a 400 Bad Request response will be sent. If you want to allow multiple values, you must bind to a `List<T>`.

### Header Bindings

The following operation method binds the header named `X-API-Key` to the `apiKey` parameter:

```dart
class CityController extends ResourceController {
  @Operation.get()
  Future<Response> getAllCities(@Bind.header('x-api-key') String apiKey) async {
    if (!isValid(apiKey)) {
      return new Response.unauthorized();
    }

    return new Response.ok(['Atlanta', 'Madison', 'Mountain View']);
  }
}
```

If an `X-API-Key` header is present in the request, its value will be available in `apiKey`. If it is not, `getAllCities(apiKey)` would not be called and a 400 Bad Request response will be sent. If `apiKey` were optional, the method is called as normal and `apiKey` is null or a default value.

Header names are case-insensitive per the HTTP specification. Therefore, the header name may be 'X-API-KEY', 'X-Api-Key' 'x-api-key', etc. and `apiKey` will be bound in all cases.

### Query Parameter Bindings

The following operation methods binds the query parameter named 'name' to the parameter `cityName`:

```dart
class CityController extends ResourceController {
  @Operation.get()
  Future<Response> getAllCities(@Bind.query('name') String cityName) async {
    return new Response.ok(cities.where((c) => c.name == cityName).toList());
  }
}
```

Query parameters can be required or optional. If required, a 400 Bad Request response is sent and no operation method is called if the query parameter is not present in the request URL. If optional, the bound variable is null or a default value.

Query parameters are case-sensitive; this binding will only match the query parameter 'name', but not 'Name' or 'NAME'.

Query parameters may also bound for query strings in the request body when the content-type is 'application/x-www-form-urlencoded'.

### Path Variable Bindings

The following operation method binds the path variable 'id' to the parameter `cityID`:

```dart
class CityController extends ResourceController {
  @Operation.get('id')
  Future<Response> getCityByID(@Bind.query('id') String cityID) async {
    return new Response.ok(cities.where((c) => c.id == cityID).toList());
  }
}
```

Path variables are made available when creating [routes](routing.md). A `Router` must have a route that includes a path variable and that path variable must be listed in the `Operation` annotation. Path variables are case-sensitive and may not be optional.

If you attempt to bind a path variable that is not present in the `Operation`, you will get a runtime exception at startup. You do not have to bind path variables for an operation method to be invoked.

### HTTP Request Body Bindings

The body of an HTTP request can also be bound to a parameter:

```dart
class CityController extends ResourceController {
  CityController(this.context);

  final ManagedContext context;

  @Operation.post()
  Future<Response> addCity(@Bind.body() City city) async {
    final insertedCity = await context.insertObject(city);

    return new Response.ok(insertedCity);
  }
}
```

Since there is only one request body, `Bind.body()` doesn't take any identifying arguments.

The bound parameter type (`City` in this example) must implement `Serializable`. Aqueduct will automatically decode the request body from it's content-type, create a new instance of the bound parameter type, and invoke its `read` method. In the above example, a valid request body would be the following JSON:

```json
{
  "id": 1,
  "name": "Atlanta"
}
```

!!! note "HTTP Body Decoding"
    Request bodies are decoded according to their content-type prior to being deserialized. For more information on request body decoding, including decoding content-types other than JSON, see [this guide](request_and_response.md).

If parsing fails or `read` throws an exception, a 400 Bad Request response will be sent and the operation method won't be called.

You may also bind `List<Serializable>` parameters to the request body. Consider the following JSON that contains a list of cities:

```json
[
  {"id": 1, "name": "Atlanta"},
  {"id": 2, "name": "Madison"}
]
```

This body can be bound by declaring the bound parameter to be a `List` of the desired type:

```dart
Future<Response> addCity(@Bind.body() List<City> cities)
```

!!! tip "List vs Object"
    An endpoint should either take a single object or a list of objects, but not both. If the request body is a JSON list and the bound variable is not a list, a 400 Bad Request response will be sent (and vice versa). Declaring a body binding of the appropriate type validates the expected value and aids in automatically generating an OpenAPI specification for your application.

Note that if the request's `Content-Type` is 'x-www-form-urlencoded', its must be bound with `Bind.query` and not `Bind.body`.

!!! tip "Key Filters in Bind.body()"
      Filters can be applied to keys of the object being read. Filters can ignore keys, require keys or throw an error if a key is found. See more [here](../http/request_and_response.md).

### Property Binding

The properties of an `ResourceController`s may also have `Bind.query` and `Bind.header` metadata. This binds values from the request to the `ResourceController` instance itself, making them accessible from *all* operation methods.

```dart
class CityController extends ResourceController {
  @requiredBinding
  @Bind.header("x-timestamp")
  DateTime timestamp;

  @Bind.query("limit")
  int limit;

  @Operation.get()
  Future<Response> getCities() async {
      // can use both limit and timestamp
  }
}
```

In the above, both `timestamp` and `limit` are bound prior to `getCities` being invoked. By default, a bound property is optional. Adding an `requiredBinding` annotation changes a property to required. If required, any request without the required property fails with a 400 Bad Request status code and none of the operation methods are invoked.

## Other ResourceController Behavior

Besides binding, `ResourceController`s have some other behavior that is important to understand.

### Request and Response Bodies

An `ResourceController` can limit the content type of HTTP request bodies it accepts. By default, an `ResourceController` will accept only `application/json` request bodies for its `POST` and `PUT` methods. This can be modified by setting the `acceptedContentTypes` property in the constructor.

```dart
class UserController extends ResourceController {
  UserController() {
    acceptedContentTypes = [ContentType.JSON, ContentType.XML];
  }
}
```

If a request is made with a content type other than the accepted content types, the controller automatically responds with a 415 Unsupported Media Type response.

The body of an HTTP request is decoded if the content type is accepted and there exists a operation method to handle the request. The body is not decoded if there is not a matching operation method for the request. The body is decoded by `ResourceController` prior to your operation method being invoked. Therefore, you can always use the synchronous `RequestBody.as` method to access the body from within an operation method:

```dart
@Operation.post()
Future<Response> createThing() async {
  // do this:
  Map<String, dynamic> bodyMap = request.body.as();

  // no need to do this:
  Map<String, dynamic> bodyMap = await request.body.decode();

  return ...;
}
```

An `ResourceController` can also have a default content type for its responses. By default, this is `application/json`. This default can be changed by changing `responseContentType` in the constructor:

```dart
class UserController extends ResourceController {
  UserController() {
    responseContentType = ContentType.XML;
  }
}
```

The `responseContentType` is the *default* response content type. An individual `Response` may set its own `contentType`, which takes precedence over the `responseContentType`. For example, the following controller returns JSON by default, but if the request specifically asks for XML, that's what it will return:

```dart
class UserController extends ResourceController {
  UserController() {
    responseContentType = ContentType.JSON;
  }

  @Operation.get('id')
  Future<Response> getUserByID(@Bind.path('id') int id) async {
    var response = new Response.ok(...);

    if (request.headers.value(Bind.headers.ACCEPT).startsWith("application/xml")) {
      response.contentType = ContentType.XML;
    }

    return response;
  }
}
```

### More Specialized ResourceControllers

Many `ResourceController` subclasses will execute [queries](../db/executing_queries.md). There are helpful `ResourceController` subclasses for reducing boilerplate code.

A `QueryController<T>` builds a `Query<T>` based on the incoming request. If the request has a body, this `Query<T>`'s `values` property is read from that body. If the request has a path variable, the `Query<T>` assigns an expression to the primary key value. For example, in a normal `ResourceController` that responds to a PUT request, you might write the following:

```dart
@Operation.put('id')
Future<Response> updateUser(@Bind.path('id') int id, @Bind.body() User user) async {
  var query = new Query<User>(context)
    ..where((u) => u.id).equalTo(id)
    ..values = user;

  return new Response.ok(await query.updateOne());
}
```

A `QueryController<T>` builds this query before a operation method is invoked, storing it in the inherited `query` property. A `ManagedObject<T>` subclass is the type argument to `QueryController<T>`.

```dart
class UserController extends QueryController<User> {
  UserController(ManagedContext context) : super(context);

  @Operation.put('id')
  Future<Response> updateUser(@Bind.path('id') int id) async {
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
  .link(() => new ManagedObjectController<User>(context));
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
  UserController(ManagedContext context) : super(context);

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

See the chapter on [validations](../db/validations.md), which are powerful when combined with `ManagedObjectController<T>`.
