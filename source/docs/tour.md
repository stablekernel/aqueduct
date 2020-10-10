# Aqueduct: A Tour

The tour demonstrates many of Aqueduct's features.

### Command-Line Interface (CLI)

The `aqueduct` command line tool creates, runs and documents Aqueduct applications; manages database migrations; and manages OAuth client identifiers. Install by running `pub global activate aqueduct` on a machine with Dart installed.

Create and run an application:

```
aqueduct create my_app
cd my_app/
aqueduct serve
```

### Initialization

An Aqueduct application starts at an [ApplicationChannel](application/channel.md). You subclass it once per application to handle initialization tasks like setting up routes and database connections. An example application looks like this:

```dart
import 'package:aqueduct/aqueduct.dart';

class TodoApp extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    context = ManagedContext(...);
  }

  @override
  Controller get entryPoint {
    final router = Router();

    router
      .route("/projects/[:id]")
      .link(() => ProjectController(context));

    return router;
  }
}
```

### Routing

A [router](http/routing.md) determines which controller object should handle a request. The *route specification syntax* is a concise syntax to construct routes with variables and optional segments in a single statement.

```dart
@override
Controller get entryPoint {
  final router = Router();

  // Handles /projects, /projects/1, /projects/2, etc.
  router
    .route("/projects/[:id]")
    .link(() => ProjectController());

  // Handles any route that starts with /file/
  router
    .route("/file/*")
    .link(() => FileController());

  // Handles the specific route /health
  router
    .route("/health")
    .linkFunction((req) async => Response.ok(null));

  return router;
}    
```

## Controllers

[Controllers](http/controller.md) handle requests. A controller handles a request by overriding its `handle` method. This method either returns a response or a request. If a response is returned, that response is sent to the client. If the request is returned, the linked controller handles the request.

```dart
class SecretKeyAuthorizer extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    if (request.raw.headers.value("x-secret-key") == "secret!") {
      return request;
    }

    return Response.badRequest();
  }
}
```

This behavior allows for middleware controllers to be linked together, such that a request goes through a number of steps before it is finally handled.

All controllers execute their code in an exception handler. If an exception is thrown in your controller code, a response with an appropriate error code is returned. You subclass `HandlerException` to provide error response customization for application-specific exceptions.

### ResourceControllers

[ResourceControllers](http/resource_controller.md) are the most often used controller. Each operation - e.g. `POST /projects`, `GET /projects` and `GET /projects/1` - is mapped to methods in a subclass. Parameters of those methods are annotated to bind the values of the request when the method is invoked.

```dart
import 'package:aqueduct/aqueduct.dart'

class ProjectController extends ResourceController {    
  @Operation.get('id')
  Future<Response> getProjectById(@Bind.path("id") int id) async {
    // GET /projects/:id
    return Response.ok(...);
  }

  @Operation.post()
  Future<Response> createProject(@Bind.body() Project project) async {
    // POST /project
    final inserted = await insertProject(project);
    return Response.ok(inserted);
  }

  @Operation.get()
  Future<Response> getAllProjects(
    @Bind.header("x-client-id") String clientId,
    {@Bind.query("limit") int limit: 10}) async {
    // GET /projects
    return Response.ok(...);
  }
}
```

### ManagedObjectControllers

`ManagedObjectController<T>`s are `ResourceController`s that automatically map a REST interface to database queries; e.g. `POST` inserts a row, `GET` gets all row of a type. They do not need to be subclassed, but can be to provide customization.

```dart
router
  .route("/users/[:id]")
  .link(() => ManagedObjectController<Project>(context));
```

## Configuration

An application's configuration is written in a YAML file. Each environment your application runs in (e.g., locally, under test, production, development) has different values for things like the port to listen on and database connection credentials. The format of a configuration file is defined by your application. An example looks like:

```
// config.yaml
database:
  host: api.projects.com
  port: 5432
  databaseName: project
port: 8000
```

Subclass `Configuration` and declare a property for each key in your configuration file:

```dart
class TodoConfig extends Configuration {
  TodoConfig(String path) : super.fromFile(File(path));

  DatabaseConfiguration database;
  int port;
}
```

The default name of your configuration file is `config.yaml`, but can be changed at the command-line. You create an instance of your configuration from the configuration file path from your application options:

```dart
import 'package:aqueduct/aqueduct.dart';

class TodoApp extends ApplicationChannel {
  @override
  Future prepare() async {
    var options = TodoConfig(options.configurationFilePath);
    ...
  }
}
```

### Running and Concurrency

Aqueduct applications are run with the `aqueduct serve` command line tool. You can attach debugging and instrumentation tools and specify how many threads the application should run on:

```
aqueduct serve --observe --isolates 5 --port 8888
```

Aqueduct applications are multi-isolate (multi-threaded). Each isolate runs a replica of the same web server with its own set of services like database connections. This makes behavior like database connection pooling implicit.

## PostgreSQL ORM

The `Query<T>` class configures and executes database queries. Its type argument determines what table is to be queried and the type of object you will work with in your code.

```dart
import 'package:aqueduct/aqueduct.dart'

class ProjectController extends ResourceController {
  ProjectController(this.context);

  final ManagedContext context;

  @Operation.get()
  Future<Response> getAllProjects() async {
    final query = Query<Project>(context);

    final results = await query.fetch();

    return Response.ok(results);
  }
}
```

Configuration of the query - like its `WHERE` clause - are configured through a fluent, type-safe syntax. A property selector identifies which column of the table to apply an expression to. The following query fetches all project's due in the next week and includes their tasks by joining the related table.

```dart
final nextWeek = DateTime.now().add(Duration(days: 7));
final query = Query<Project>(context)
  ..where((project) => project.dueDate).isLessThan(nextWeek)
  ..join(set: (project) => project.tasks);
final projects = await query.fetch();
```

Rows are inserted or updated by setting the statically-typed values of a query.

```dart
final insertQuery = Query<Project>(context)
  ..values.name = "Build an aqueduct"
  ..values.dueDate = DateTime(year, month);
var newProject = await insertQuery.insert();  

final updateQuery = Query<Project>(context)
  ..where((project) => project.id).equalTo(newProject.id)
  ..values.name = "Build a miniature aqueduct";
newProject = await updateQuery.updateOne();  
```

`Query<T>`s can perform sorting, joining and paging queries.

```dart
final overdueQuery = Query<Project>(context)
  ..where((project) => project.dueDate).lessThan(DateTime().now())
  ..sortBy((project) => project.dueDate, QuerySortOrder.ascending)
  ..join(object: (project) => project.owner);

final overdueProjectsAndTheirOwners = await query.fetch();
```

Controllers will interpret exceptions thrown by queries to return an appropriate error response to the client. For example, unique constraint conflicts return 409, missing required properties return 400 and database connection failure returns 503.

### Defining a Data Model

To use the ORM, you declare your tables as Dart types and create a subclass of `ManagedObject<T>`. A subclass maps to a table in the database, each instance maps to a row, and each property is a column. The following declaration will map to a table named `_project` with columns `id`, `name` and `dueDate`.

```dart
class Project extends ManagedObject<_Project> implements _Project {
  bool get isPastDue => dueDate.difference(DateTime.now()).inSeconds < 0;
}

class _Project  {
  @primaryKey
  int id;

  @Column(indexed: true)
  String name;

  DateTime dueDate;
}
```

Managed objects have relationships to other managed objects. Relationships can be has-one, has-many and many-to-many. A relationship is always two-sided - the related types must declare a property that references each other.

```dart
class Project extends ManagedObject<_Project> implements _Project {}
class _Project {
  ...

  // Project has-many Tasks
  ManagedSet<Task> tasks;
}

class Task extends ManagedObject<_Task> implements _Task {}
class _Task {
  ...

  // Task belongs to a project, maps to 'project_id' foreign key column
  @Relate(#tasks)
  Project project;
}
```

`ManagedObject<T>`s are serializable and can be directly read from a request body, or encoded as a response body.

```dart
class ProjectController extends ResourceController {
  @Operation.put('id')
  Future<Response> updateProject(@Bind.path('id') int projectId, @Bind.body() Project project) async {
    final query = Query<Project>(context)
      ..where((project) => project.id).equalTo(projectId)
      ..values = project;

    return Response.ok(await query.updateOne());
  }
}
```

### Database Migrations

The CLI will automatically generate database migration scripts by detecting changes to your managed objects. The following, when ran in a project directory, will generate and execute a database migration.

```
aqueduct db generate
aqueduct db upgrade --connect postgres://user:password@host:5432/database
```

You can edit migration files by hand to alter any assumptions or enter required values, and run `aqueduct db validate` to ensure the changes still yield the same schema. Be sure to keep generated files in version control.

## OAuth 2.0

An OAuth 2.0 server implementation handles authentication and authorization for Aqueduct applications. You create an `AuthServer` and its delegate as services in your application. The delegate is configurable and manages how tokens are generated and stored. By default, access tokens are a random 32-byte string and client identifiers, tokens and access codes are stored in your database using the ORM.

```dart
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/managed_auth.dart';

class AppApplicationChannel extends ApplicationChannel {
  AuthServer authServer;
  ManagedContext context;

  @override
  Future prepare() async {
    context = ManagedContext(...);

    final delegate = ManagedAuthDelegate<User>(context);
    authServer = AuthServer(delegate);
  }  
}
```

Built-in authentication controllers for exchanging user credentials for access tokens are named `AuthController` and `AuthCodeController`. `Authorizer`s are middleware that require a valid access token to access their linked controller.

```dart
Controller get entryPoint {
  final router = Router();

  // POST /auth/token with username and password (or access code) to get access token
  router
    .route("/auth/token")
    .link(() => AuthController(authServer));

  // GET /auth/code returns login form, POST /auth/code grants access code
  router
    .route("/auth/code")
    .link(() => AuthCodeController(authServer));

  // ProjectController requires request to include access token
  router
    .route("/projects/[:id]")
    .link(() => Authorizer.bearer(authServer))
    .link(() => ProjectController(context));

  return router;
}
```

The CLI has tools to manage OAuth 2.0 client identifiers and access scopes.

```
aqueduct auth add-client \
  --id com.app.mobile \
  --secret foobar \
  --redirect-uri https://somewhereoutthere.com \
  --allowed-scopes "users projects admin.readonly"
```

## Logging

All requests are logged to an application-wide logger. Set up a listener for the logger in `ApplicationChannel` to write log messages to the console or another medium.

```dart
class WildfireChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    logger.onRecord.listen((record) {
      print("$record");
    });
  }
}
```

## Testing

Aqueduct tests start a local version of your application and execute requests. You write expectations on the responses. A [TestHarness](testing/tests.md) manages the starting and stopping of an application, and exposes a default `Agent` for executing requests. An `Agent` can be configured to have default headers, and multiple agents can be used within the same test.

```dart
import 'harness/app.dart';

void main() {
  final harness = TestHarness<TodoApp>()..install();

  test("GET /projects returns all projects" , () async {
    var response = await harness.agent.get("/projects");
    expectResponse(response, 200, body: every(partial({
      "id": greaterThan(0),
      "name": isNotNull,
      "dueDate": isNotNull
    })));
  });
}
```

### Testing with a Database

Aqueduct's ORM uses PostgreSQL as its database. Before your tests run, Aqueduct will create your application's database tables in a local PostgreSQL database. After the tests complete, it will delete those tables. This allows you to start with an empty database for each test suite as well as control exactly which records are in your database while testing, but without having to manage database schemas or use an mock implementation (e.g., SQLite).

This behavior, and behavior for managing applications with an OAuth 2.0 provider, are available as [harness mixins](testing/mixins.md).

## Documentation

OpenAPI documents describe your application's interface. These documents can be used to generate documentation and client code. A document can be generated by reflecting on your application's codebase, just run the `aqueduct document` command.

The `aqueduct document client` command creates a web page that can be used to configure issue requests specific to your application.
