![Aqueduct](https://raw.githubusercontent.com/stablekernel/aqueduct/master/images/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

[![Gitter](https://badges.gitter.im/dart-lang/server.svg)](https://gitter.im/dart-lang/server?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Aqueduct is a server-side framework for building and deploying REST applications. It is written in Dart. Its goal to provide am integrated and consistently styled framework.

It contains behavior for routing and authorizing HTTP requests, persisting data in PostgreSQL, testing, and much more. The `aqueduct` command-line tool serves applications, manages database schemas and OAuth 2.0 clients, and generates OpenAPI specifications.

Aqueduct is well-tested, documented and adheres to semantic versioning.

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Create a new project.

        aqueduct create my_project

Open the project directory in an [IntelliJ IDE](https://www.jetbrains.com/idea/download/), [Atom](https://atom.io) or [Visual Studio Code](https://code.visualstudio.com). All three IDEs have a Dart plugin.

## Tutorials and Documentation

Step-by-step tutorials for beginners are available [here](https://aqueduct.io/docs/tut/getting-started).

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest) or you can install it in [Dash](https://kapeli.com/docsets#dartdoc).

You can find in-depth guides [here](https://aqueduct.io/docs/).

## Tour

Take a tour of Aqueduct.

### Initialization

Create applications with the command line tool:

```
aqueduct create my_app
```

A subclass of `RequestSink` initializes the application by setting up routes, database connections and other resources used to serve requests.

```dart
import 'package:aqueduct/aqueduct.dart';

class AppRequestSink extends RequestSink {
  ManagedContext databaseContext;

  AppRequestSink(ApplicationConfig config) : super(config) {
    databaseContext = contextFrom(config);
  }

  @override
  void setupRouter(Router router) {
    router
      .route("/resource")
      .generate(() => new ResourceController(databaseContext));
  }
}
```

### Routing

Build complex routes with path variables, create route groups via optional path segments:

```dart
  router
    .route("/users/[:id]")
    .generate(() => new UserController());

  router
    .route("/file/*")
    .generate(() => new HTTPFileController());
```

Middleware can be inserted to pre-process or reject requests before they reach the next stage.

```dart
router
  .route("/users/[:id]")
  .pipe(new Authorizer(authServer))
  .generate(() => new UserController());
```

### Controllers

HTTP requests are bound to *responder methods* implemented in `HTTPController` subclasses. A single `HTTPController` subclass handles all HTTP methods for resource, e.g. POST /users, GET /users and GET /users/1 all go to the same controller.

```dart
import 'package:aqueduct/aqueduct.dart'

class ResourceController extends HTTPController {
  @httpGet
  Future<Response> getAllResources() async {
    return new Response.ok(await fetchResources());
  }

  @httpGet
  Future<Response> getResourceByID(@HTTPPath("id") int id) async {
    return new Response.ok(await fetchResource(id));
  }

  @httpPost
  Future<Response> createResource(@HTTPBody() Resource resource) async {
    var inserted = await insertResource(resource);
    return new Response.ok(inserted);
  }
}
```

Values from the request can be read by accessing the `request` property or can be bound to responder method arguments:

```dart
class ResourceController extends HTTPController {
  @httpGet
  Future<Response> getAllResources(
      @HTTPHeader("x-request-id") String requestID,
      {@HTTPQuery("limit") int limit}) async {
    return new Response.ok(await fetchResources(limit ?? 0));
  }

  @httpPost
  Future<Response> createResource() async {
    var resource = new Resource()..readFromMap(request.body.asMap());
    var inserted = await insertResource(resource);
    return new Response.ok(inserted);
  }
}
```

`ManagedObjectController<T>`s are specialized `HTTPController`s that map a REST interface to database queries without writing any code:

```dart
router
  .route("/users/[:id]")
  .generate(() => new ManagedObjectController<User>());
```

`RequestController`s are a more generic controller that has a single method to either respond to requests or process them in some way. A `RequestController` is the base class for middleware, `HTTPController` and anything else that can handle a request.

```dart
class VerifyingController extends RequestController {
  @override
  Future<RequestOrResponse> processRequest(Request request) async {
    if (request.innerRequest.headers.value("x-secret-key") == "secret!") {
      return request;
    }

    return new Response.badRequest();
  }
}
```

All controllers catch exceptions and translate them to the appropriate status code response.

### Configuration

Read YAML configuration data into type-safe and name-safe structures at startup:

```
// config.yaml
database:
  host: ...
  port: 5432
  databaseName: foo
otherOption: hello
numberOfDoodads: 3  
```

```dart
import 'package:aqueduct/aqueduct.dart';

class AppRequestSink extends RequestSink {
  AppRequestSink(ApplicationConfig config) : super(config) {
    var options = new AppOptions(config.configurationFilePath);
    ...
  }
}

class AppOptions extends ConfigurationItem {
  AppOptions(String path) : super.fromFile(path);
  DatabaseConnectionInfo database;
  String otherOption;
  int numberOfDoodads;
}
```

### Running and Concurrency

Aqueduct applications are run with the `aqueduct` command line tool, which can also open debugging and instrumentation tools and specify how many threads the application should run on:

```
aqueduct serve --observe --isolates 5
```

Run applications detached or still connected to the shell:

```
aqueduct serve --detached --port $PORT
```

Aqueduct applications are multi-isolate (multi-threaded). Each isolate runs a replica of the same web server with its own set of resources like database connections. This makes behavior like database connection pooling implicit and painless.

### Querying a Database

Aqueduct applications have a built-in ORM. Database commands are executed with instances of `Query<T>`.

```dart
import 'package:aqueduct/aqueduct.dart'

class ResourceController extends HTTPController {
  @httpGet
  Future<Response> getAllResources() async {
    var query = new Query<Resource>();

    var results = await query.fetch();

    return new Response.ok(results);
  }
}
```

The results of a `Query<T>` can be filtered by configuring the `Query.where` property, which uses Dart's powerful, real-time static analyzer to avoid mistakes and offer code completion.

```dart
var query = new Query<Employee>()
  ..where.name = whereStartsWith("Sa")
  ..where.salary = whereGreaterThan(50000);
var results = await query.fetch();
```

Building a query to insert or update values leverages the same behavior:

```dart
var query = new Query<Employee>()
  ..values.name = "Bob"
  ..values.salary = 50000;

var bob = await query.insert();  

var updateQuery = new Query<Employee>()
  ..where.id = bob.id
  ..values.name = "Bobby";
bob = await updateQuery.updateOne();  
```

`Query<T>`s can sort and page on a result set. It can also join tables and return objects and their relationships:

```dart
var query = new Query<Employee>()
  ..where.name = "Sue Gallagher"
  ..join(object: (e) => e.manager)
  ..join(set: (e) => e.directReports);

var herAndHerManagerAndHerDirectReports = await query.fetchOne();
```

Exceptions thrown for queries are caught by a controller and translated into the appropriate status code. Unique constraint conflicts return 409,
missing required properties return 400, database connection failure returns 503, etc. You can change this by catching exceptions from `Query<T>` methods.

### Defining a Data Model

Rows in databases are represented by instances of `ManagedObject<T>` subclasses. These subclasses are the type argument to `Query<T>`. They are made up of two classes: one that declares a property for each database column in a table and the subclass of `ManagedObject<T>` that you work with in your code.

```dart
class Employee extends ManagedObject<_Employee> implements _Employee {
  bool get wasRecentlyHired => hireDate.difference(new DateTime.now()).inDays < 30;
}
class _Employee  {
  @managedPrimaryKey
  int index;

  @ManagedColumnAttributes(indexed: true)
  String name;

  DateTime hireDate;
  int salary;
}
```

`ManagedObject<T>`s have relationship properties for has-one, has-many and many-to-many references to other `ManagedObject<T>`s. The property with `ManagedRelationship` metadata is a foreign key column.

```dart
class Employee extends ManagedObject<_Employee> implements _Employee {}
class _Employee {
  ...

  ManagedSet<Initiative> initiatives;
}

class Initiative extends ManagedObject<_Initiative> implements _Initiative {}
class _Initiative {
  ...

  @ManagedRelationship(#initiatives)
  Employee leader;
}
```

`ManagedObject<T>`s are easily read from and written to JSON (or any other format):

```dart
class UserController extends HTTPController {
  @httpPut
  Future<Response> updateUser(@HTTPPath("id") int id, @HTTPBody() User user) async {
    var query = new Query<User>()
      ..where.id = id
      ..values = user;

    var updatedUser = await query.updateOne();

    return new Response.ok(updatedUser);
  }
}
```

### Automatic Database Migration

Generate and run database migrations with the `aqueduct db` tool:

```
aqueduct db generate
aqueduct db validate
aqueduct db upgrade --connect postgres@://...
```

### OAuth 2.0

Authentication and authorization are enabled at application startup by creating an `AuthServer` with `ManagedAuthStorage`:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppRequestSink extends RequestSink {
  AppRequestSink(ApplicationConfig config) : super(config) {
    var storage = new ManagedAuthStorage<User>(ManagedContext.defaultContext);
    authServer = new AuthServer(storage);
  }

  AuthServer authServer;
}
```

Set up routes to exchange credentials for tokens using `AuthController` and `AuthCodeController`. Add `Authorizer`s between routes and their controller to restrict access to authorized resource owners only:

```dart
void setupRouter(Router router) {
  router
    .route("/auth/token")
    .generate(() => new AuthController(authServer));

  router
    .route("/auth/code")
    .generate(() => new AuthCodeController(authServer));

  router
    .route("/protected")
    .pipe(new Authorizer.bearer(authServer))
    .generate(() => new ProtectedController());
}
```

Insert OAuth 2.0 clients into a database:

```
aqueduct auth add-client --id com.app.mobile --secret foobar --redirect-uri https://somewhereoutthere.com
```

### Logging

All requests are logged to an instance of `Logger`. Set up a listener for logger in `RequestSink` to print log messages to the console. (See also [scribe](https://pub.dartlang.org/packages/scribe) for logging to rotating files.)


```dart
class WildfireSink extends RequestSink {
  WildfireSink(ApplicationConfiguration config) : super(config) {
    logger.onRecord.listen((record) {
      print("$record");
    });
  }
}
```

### Testing

Tests are run by starting the Aqueduct application and verifying responses in a test file. A test harness is included in projects generated from `aqueduct create` that starts and stops a test instance of your application and uploads your database schema to a temporary, local database.

```dart
import 'harness/app.dart';

void main() {
  var app = new TestApplication();

  setUpAll(() async {
    await app.start();
  });

  test("...", () async {
    var response = await app.client.request("/endpoint").get();
    ...
  });
}
```

A `TestClient` executes requests configured for the locally running test instance of your application. Instances of `TestResponse` are returned and can be evaluated with matchers like any other Dart tests. There are special matchers specifically for Aqueduct.

```dart
test("POST /users creates a user", () async {
  var request = app.client.request("/users")
    ..json = {"email": "bob@stablekernel.com"};
  var response = await request.post();

  expect(response, hasResponse(200, {
    "id": isNumber,
    "email": "bob@stablekernel.com"
  }));
});

test("GET /users/1 returns a user", () async {
  var response = await app.client.authenticatedRequest("/users/1").get();
  expect(response, hasResponse(200, partial({
    "email": "bob@stablekernel.com"
  })));
});
```

### Documentation

Generate OpenAPI specifications automatically:

```
aqueduct document
```
