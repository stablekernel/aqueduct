![Aqueduct](img/aqueduct.png)

Aqueduct is a productive server-side framework written in Dart.

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

## Getting Started

Make sure to check out the tutorial in the navigation menu.

1. [Install Dart](https://www.dartlang.org/install).
2. Activate the Aqueduct Command-Line Tool

        pub global activate aqueduct

3. Run first time setup (this prompts you to setup a local PostgreSQL database for testing).

        aqueduct setup

4. Create a new project.

        aqueduct create my_project

The recommended IDE is [IntelliJ IDEA CE](https://www.jetbrains.com/idea/download/) (or any other IntelliJ platform, like Webstorm) with the [Dart Plugin](https://plugins.jetbrains.com/idea/plugin/6351-dart). (The plugin can be installed directly from the IntelliJ IDEA plugin preference pane.)

Other editors with good Dart plugins are [Atom](https://atom.io) and [Visual Studio Code](https://code.visualstudio.com).

In any of these editors, open the project directory created by `aqueduct create`.

## Other Important References

Deeper dives into the framework are available under the Guides in the sidebar.

[Aqueduct API Reference](https://www.dartdocs.org/documentation/aqueduct/latest).

[Aqueduct on Github](https://github.com/stablekernel/aqueduct).


## Tour

Take a tour of Aqueduct.

### Initialization

Create applications with the command line tool:

```
aqueduct create my_app
```

And subclass a `RequestSink` to declare routes:

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
    .generate(() => new StaticFileController());
```

### Controllers

The class most often used to respond to a request is `HTTPController`. `HTTPController`s must be subclassed and are declared in their own file. An `HTTPController` handles all HTTP requests for a resource; e.g. POST /users, GET /users and GET /users/1 all go to the same controller.

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
}
```

Use `ManagedObjectController<T>`s that map a REST interface to database queries without writing any code:

```dart
router
  .route("/users/[:id]")
  .generate(() => new ManagedObjectController<User>());
```

Controllers catch exceptions and translate them to the appropriate status code response.

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
  DatabaseConnectionInfo database;
  String otherOption;
  int numberOfDoodads;
}
```

### Running and Concurrency

Aqueduct applications are run with a command line tool, which can also open debugging and instrumentation tools and specify how many threads the application should run on:

```
aqueduct serve --observe --isolates 5
```

Run applications detached or still connected to the shell (how a tool like Heroku expects):

```
aqueduct serve --detached --port $PORT
```

Aqueduct applications threads are isolated - they share no memory with other threads - and each runs a replica of the same web server. Pooling resources is effectively achieved through this mechanism.

### Querying a Database

Much of the time, a request is handled by sending one or more commands to a database to either get data or send data. This is done with `Query<T>` objects.

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

The results of a `Query<T>` can be filtered by configuring its `where` property, which uses Dart's powerful, real-time static analyzer to avoid mistakes and offer code completion.

```dart
var query = new Query<Employee>()
  ..where.name = whereStartsWith("Sa")
  ..where.salary = whereGreaterThan(50000);
var results = await query.fetch();
```

Building queries to insert or update values into the database uses the similar `values` property of a `Query<T>`.

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
  ..joinOne((e) => e.manager)
  ..joinMany((e) => e.directReports);

var herAndHerManagerAndHerDirectReports = await query.fetchOne();
```

Exceptions thrown for queries are caught by the controller and translated into the appropriate status code. Unique constraint conflicts return 409,
missing required properties return 400, database connection failure returns 503, etc. You can change this by try-catching `Query<T>` methods.

### Defining a Data Model

For each database table, there is a `ManagedObject<T>` subclass. These subclasses are the type argument to `Query<T>`. They are made up of two classes: a persistent type that declares a property for each database column in the table, and the subclass of `ManagedObject<T>` that you work with in your code.

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

`ManagedObject<T>`s have relationship properties - references to other `ManagedObject<T>`s. The property with `ManagedRelationship` metadata is a foreign key column.

```dart
class Employee extends ManagedObject<_Employee> implements _Employee {}
class _Employee {
  ManagedSet<Initiative> initiatives;

  ...
}

class Initiative extends ManagedObject<_Initiative> implements _Initiative {}
class _Initiative {
  @ManagedRelationship(#initiatives)
  Employee leader;

  ...
}
```

`ManagedObject<T>`s are easily read from and written to JSON (or any other format):

```dart
class UserController extends HTTPController {
  @httpPut
  Future<Response> updateUser(@HTTPPath("id") int id) async {
    var query = new Query<User>()
      ..where.id = id
      ..values = (new User()..readMap(request.body.asMap());

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

Logging can write to stdout or a rotating log file. Logging runs on its own thread; API threads send messages to the logging thread which handles I/O.

```dart
class WildfireSink extends RequestSink {
  static String LoggingTargetKey = "logging";

  static Future initializeApplication(ApplicationConfiguration config) async {    
    ...
    var loggingServer = new LoggingServer([new ConsoleBackend()]);
    await loggingServer?.start();
    config.options[LoggingTargetKey] = loggingServer?.getNewTarget();
  }

  WildfireSink(ApplicationConfiguration config) : super(config) {
    var target = config.options[LoggingTargetKey];
    target?.bind(logger);

    logger.info("We're up!");
  }
}
```

### Testing

Because Aqueduct can generate database migration files, it can generate your application data model on the fly, too. Starting a test instance of an application will connect to a temporary database and create tables that are destroyed when the database connection closes. Endpoints are validated with specialized matchers in the Hamcrest matcher style:

```dart
test("/users/1 returns a user", () async {
  var response = await testClient.authenticatedRequest("/users/1").get();
  expect(response, hasResponse(200, partial({
    "id": 1,
    "name": isString
  })));
});
```

Use the template project's test harness to quickly set up tests:

```dart
import 'package:test/test.dart';
import 'package:my_app/my_app.dart';

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

### Documentation

Generate OpenAPI specifications automatically:

```
aqueduct document
```
