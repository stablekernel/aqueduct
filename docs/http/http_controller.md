# HTTPController

The overwhelming majority of Aqueduct code is written in subclasses of `HTTPController`. Instances of this class receive requests for a particular resource. For example, an `HTTPController` might handle requests to create, update, delete, read and list users.

An `HTTPController` works by selecting one of its methods to respond to a request. This selection is based on the HTTP method and path variables of the request. For example, a `POST /users` would trigger a `createUser` method to be invoked, whereas a `GET /users/1` would trigger its `getUserByID` method. The names of these methods are up to you; the method that gets called is determined by metadata on the method and its parameters.

### Responder Methods

A method that handles a request in an `HTTPController` subclass is called a *responder method*. To be a responder method, a method must return a `Future<Response>` and have `HTTPMethod` metadata. Here's an example:

```dart
class UserController extends HTTPController {
  @httpGet
  Future<Response> getAllUsers() async {
    return new Response.ok(await getUsersFromDatabase());
  }
}
```

The constant `httpGet` is an instance of `HTTPMethod`. When a `GET` request is sent to an instance of `UserController`, this method is invoked and the `Response` it returns is sent to the HTTP client. There exist `HTTPMethod` constants for the major HTTP methods: `httpPut`, `httpGet`, `httpPost` and `httpDelete`. You may use `HTTPMethod` for other types of HTTP methods:

```dart
@HTTPMethod("PATCH")
Future<Response> patch() async { ... }
```

A responder method may have parameters that further qualify its selection based on the path of the HTTP request. For example, the following controller may respond to both `GET /users` and `GET /users/1`:

```dart
class UserController extends HTTPController {
  @httpGet
  Future<Response> getAllUsers() async {
    return new Response.ok(await getUsersFromDatabase());
  }

  @httpGet
  Future<Response> getOneUser(@HTTPPath("id") int id) async {
    return new Response.ok(await getAUserFromDatabaseByID(id));
  }
}
```

For this controller to work correctly, it must be hooked up to a route with an optional `id` path variable:

```dart
router
  .route("/users/[:id]")
  .generate(() => new UserController());
```

Notice that the `id` parameter in `getOneUser` has `HTTPPath` metadata. The argument to `HTTPPath` must be the name of the path variable in the route. In this example, the path variable is `id` and the argument to `HTTPPath` is the same. When a `GET` request is delivered to the controller in this example, it is checked for the path variable `id`: if it exists, `getOneUser` is invoked, otherwise `getAllUsers` is invoked.

The value of an `HTTPPath` parameter will be equal to value of the variable in the incoming request path. A path variable is a `String`, but an `HTTPPath` parameter can be another type and the value will be parsed into that type. Any type that has a static `parse(String)` method can be used as a path variable. If the `HTTPPath` parameter is a `String`, no parsing occurs.

A responder method may have multiple `HTTPPath` parameters and the order does not matter. If no responder method exists for the incoming HTTP method, a 405 status code is returned. An `HTTPController` will always respond to a request.

### Request and Response Bodies

An `HTTPController` limits the content type of HTTP request bodies it accepts. By default, an `HTTPController` will accept both `application/json` and `application/x-www-form-urlencoded` request bodies for its `POST` and `PUT` methods. This can be modified by setting the `acceptedContentTypes` property in the constructor.

```dart
class UserController extends HTTPController {
  UserController() {
    acceptedContentTypes = [ContentType.JSON, ContentType.XML];
  }
}
```

If a request is made with a content type other than the accepted content types, the controller automatically responds with a unsupported media type (status code 415) response.

The body of an HTTP request is decoded if the content type is supported and there exists a responder method to handle the request. This means two things. First, the body is not decoded if the request is going to be discarded because no responder method was found.

Second, methods on `HTTPBody` have two flavors: those that return the contents as a `Future` or those that return the already decoded body. Responder methods can access the already decoded body without awaiting on the `Future`-flavored variants of `HTTPBody`:

```dart
@httpPost
Future<Response> createThing() async {
  // do this:
  var bodyMap = request.body.asMap();

  // no need to do this:
  var bodyMap = await request.body.decodeAsMap();

  return ...;
}
```

An `HTTPController` can also have a default content type for its response bodies. By default, this is `application/json` - any response body is encoded to JSON. This default can be changed by changing `responseContentType` in the constructor:

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

  @httpGet
  Future<Response> getUserByID(@HTTPPath("id") int id) async {
    var response = new Response.ok(...);

    if (request.headers.value(HttpHeaders.ACCEPT).startsWith("application/xml")) {
      response.contentType = ContentType.XML;
    }

    return response;
  }
}
```

### Query and Header Values

The `Request` being processed can always be accessed through the `request` property of a controller. For example, if you want to check for a particular header:

```dart
@httpGet
Future<Response> getThing() async {
  if (request.innerRequest.headers.value("X-Header") != null) {
    ...
  }

  return new Response.ok(...);
}
```

`HTTPController`s can help when reading header and query parameter values from a request. A responder method can have additional parameters with either `HTTPQuery` or `HTTPHeader` metadata. For example:

```dart
Future<Response> getThing(
  @HTTPQuery("limit") int numberOfThings,
  @HTTPQuery("offset") int offset) async {
    var things = await getThingsBetween(offset, offset + numberOfThings);
    return new Response.ok(things);
}
```

If the request `/things?limit=10&offset=20` is handled by this method, `numberOfThings` will be 10 and `offset` will be 20. `HTTPQuery` and `HTTPHeader` parameters, like `HTTPPath` parameters, are always strings but can be parsed into types that implement `parse`. `HTTPHeader` metadata on parameters works the same, but read values from headers. `HTTPQuery` parameter names are case sensitive, whereas `HTTPHeader` parameter names are not.

The position of a parameter with `HTTPQuery` or `HTTPMethod` metadata in an parameter list matters. In the above example, both `limit` and `offset` are *required* in the request. If these parameters were optional parameters, the they are optional:

```dart
Future<Response> getThing(
  {@HTTPQuery("limit") int numberOfThings,
  @HTTPQuery("offset") int offset}) async {
    offset ??= 0;
    numberOfThings ??= 10;

    var things = await getThingsBetween(offset, offset + numberOfThings);
    return new Response.ok(things);
}
```

In the above example - with curly brackets (`{}`) to indicate optional - the request can omit both `limit` and `offset`. If omitted, their values are null and the controller can provide defaults. This optional vs. required behavior is true for both `HTTPQuery` and `HTTPHeader` parameters, but not for `HTTPPath`.

If a method has required query or header parameters that are not met by a request, the controller responds with a 400 status code, listing the required parameters that were missing, and *does not* invoke the responder method.

Controllers can also declare properties with `HTTPQuery` or `HTTPHeader` metadata. For example, the following controller will set its `version` property to the header `X-Version` for all requests it receives:

```dart
class VersionedController extends HTTPController {
  @HTTPHeader("x-version")
  String version;

  @httpGet
  Future<Response> getThings() async {
    // version = X-Version header from request
    ...
  }
}
```

Properties that are declared with this metadata default to optional. To make them required, add additional metadata:

```dart
class VersionedController extends HTTPController {
  @requiredHTTPParameter
  @HTTPHeader("x-version")
  String version;
  ...
}
```

If a required property has no value in the request, a 400 is returned and no responder method is called. If the property is optional and not in the request, the value is null.

`HTTPQuery` parameters will also assign values from request bodies if the content type is `application/x-www-form-urlencoded`. For example, a `POST /endpoint?param=1` sends `param=1` in the HTTP body, but it is conceptually a query string. Therefore, the following responder method would have the value `1` in its `param` parameter:

```dart
@httpPost
Future<Response> createThing(@HTTPQuery("param") int param) async {
  ...
}
```

### More Specialized HTTPControllers

Because many `HTTPController` subclasses will execute [Queries](../db/executing_queries.md), there are helpful `HTTPController` subclasses for reducing boilerplate code.

A `QueryController<T>` builds a `Query<T>` based on the incoming request. If the request has a body, this `Query<T>`'s `values` property is read from that body. If the request has a path variable, the `Query<T>` assigns a matcher to the primary key value of its `where`. For example, in a normal `HTTPController` that responds to a PUT request, you might write the following:

```dart
@httpPut
Future<Response> updateUser(@HTTPPath("id") int id) async {
  var query = new Query<User>()
    ..where.id = whereEqualTo(id)
    ..values = (new User()..readMap(request.body.asMap());

  return new Response.ok(await query.updateOne());
}
```

A `QueryController<T>` builds this query for you. The `ManagedObject<T>` subclass is the type argument to `QueryController<T>`, which has an additional `query` property that is read from the request.

```dart
class UserController extends QueryController<User> {
  // query already exists and is identical to the snippet above
  return new Response.ok(await query.updateOne());
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

### Accessing the Request

Recall that any value from the request itself can be accessed through the `request` property of a controller.

This also means that an `HTTPController` instance cannot be reused to handle multiple requests; if it awaited on an asynchronous method, a new request could be assigned to the `request` property. Therefore, all `HTTPController`s must be added to a request processing pipeline with `generate`. If you add a controller with `pipe`, an exception will be thrown immediately at startup.
