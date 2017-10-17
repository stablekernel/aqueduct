# Application Initialization and the RequestSink

The only requirement of an Aqueduct application is that it has exactly one `RequestSink` subclass. This subclass handles the initialization of an application, including setting up routes, authorization and database connections.

A `RequestSink` subclass is declared in its own file named `lib/<application_name>_request_sink.dart`, which is exported from the application library file. (For example if the application is named `wildfire`, the application library file is `lib/wildfire.dart`.)

```
wildfire/
  lib/
    wildfire.dart
    wildfire_request_sink.dart
    controllers/
      user_controller.dart      
    ...
```

Applications are run with the command line tool `aqueduct serve`. This tool create multiple `Isolate`s (a thread managed by the VM) and creates an instance of the `RequestSink` for each. Therefore, the channel of `RequestController`s created by the `RequestSink` is replicated for each isolate. Requests are divvied up among each isolate to maximize CPU and resource usage.

## Subclassing RequestSink

The responsibility of a `RequestSink` is to set up routes and initialize services it will use to fulfill requests. There are five initialization methods in `RequestSink`, each with its own purpose. The methods and the order they are executed in are as follows:

1. `RequestSink.initializeApplication`: this *static* method is called once at the very beginning of an application's startup, before any instances of `RequestSink` are created.
2. An instance of `RequestSink` is created with its default constructor.
3. The method `setupRouter` is invoked on the `RequestSink` instance; initialized properties from the constructor are injected into controllers created here.
4. The method `willOpen` is invoked on the `RequestSink` instance.
5. The method `didOpen` is invoked on the `RequestSink` instance.

Only `setupRouter` is required, but it is extremely common to provide a constructor and implement `RequestSink.initializeApplication`. It is rare to use `willOpen` and rarer still to use `didOpen`.

Aqueduct applications will create more than one instance of `RequestSink` and repeat steps 2-5 for each instance. See a later section on multi-threading in Aqueduct applications.

The usage and details for each of these initialization methods is detailed in the following sections.

### Use RequestSink.initializeApplication for One-Time Initialization

Since many instances of `RequestSink` will be created in an Aqueduct application, its instance methods and constructor will be called multiple times. An Aqueduct application may often have to execute one-time startup tasks that must not occur more than once. For this purpose, you may implement a *static* method with the following name and signature in an application's `RequestSink`:

```dart
static Future initializeApplication(ApplicationConfiguration config) async {
  ... do one time setup ...
}
```

A common use of this method is to set up services that will be shared across isolates or unique persistent connections to remote services. This method can modify `ApplicationConfiguration` prior to `RequestSink` instances being created. This allows services allocated during this one-time setup method can be accessible by each `RequestSink` instance.

For example:

```dart
static Future initializeApplication(ApplicationConfiguration config) async {        
  config.options["special item"] = "xyz";
}  

RequestSink(ApplicationConfiguration config) {
  var parsedConfigValues = config.options["special item"]; // == xyz
}
```

In a more complex example, Aqueduct applications that use [scribe](https://pub.dartlang.org/packages/scribe) will implement `initializeApplication` to optimize logging. `scribe` works by spawning a new isolate that writes log statements to disk or the console. Aqueduct isolates send their log messages to the logging isolate so that they can move on to more important things. The logging isolate is spawned in `initializeApplication` and a reference is stored in `ApplicationConfiguration`. Each `RequestSink` grabs the reference so that it can send messages to the logging isolate later.

It is important to note the behavior of isolates as it relates to Aqueduct and the initialization process. Each isolate has its own heap. `initializeApplication` is executed in the main isolate, whereas each `RequestSink` is instantiated in its own isolate. This means that any values stored in `ApplicationConfiguration` must be safe to pass across isolates - i.e., they can't contain references to closures.

Additionally, any static or global variables that are set in the main isolate *will not be set* in other isolates. Configuration types like `HTTPCodecRepository` do not share values across isolates. Therefore, they must be set up in the `RequestSink` constructor.

```dart
/// Do not do this!
static Future initializeApplication(ApplicationConfiguration config) async {        
  HTTPCodecRepository.add(new ContentType("application", "xml"), new XMLCodec());
}  
```

Also, because static methods cannot be overridden in Dart, it is important that you ensure the name and signature of `initializeApplication` exactly matches what is shown in these code samples. The analyzer can't help you here, unfortunately.

### Use RequestSink's Constructor to Initialize Service and Isolate-Specific Configurations

A service, in this context, is something your application will use to fulfill requests. A database connection is an example of a service. Services should be created the constructor of a `RequestSink` and stored as properties.

The constructor of a `RequestSink` must be unnamed and take a single argument of type `ApplicationConfiguration`. This instance of `ApplicationConfiguration` will have the same values as the instance in the previous initialization step (`initializeApplication`). The configuration contains a path to the configuration file that the application was started with (this defaults to `config.yaml`). This file often contains values that set up things like database connections:

The values in `ApplicationConfiguration` often contain the details for the services that should be created - like database connection information. Here is an example:

```dart
class MySink extends RequestSink {
  MySink(ApplicationConfiguration config) : super(config) {
    var appConfigValues = new MyConfig(config.configurationFilePath);
    var databaseConnection = new DatabaseConnection()
      ..connectionInfo = appConfigValues.database;
  }
}
```

(See more details about using configuration files [here](configure.md).)

Isolate specific initialization should also be set in this method:

```dart
class MySink extends RequestSink {
  MySink(ApplicationConfiguration config) : super(config) {
    HTTPCodecRepository.add(new ContentType("application", "xml"), new XMLCodec());
  }
}  
```

All of the properties of a `RequestSink` should be initialized in its constructor. This allows the next phase of initialization - setting up routes - to inject these services into controllers. For example, a typical `RequestSink` will have some property that holds a database connection; this property should be initialized in the constructor.

A constructor should never call asynchronous functions. Some services require asynchronous initialization - e.g., a database connection has to connect to a database - but those must be fully initialized later. (See a later section on Lazy Services.)

### Setting up Routes in setupRouter

Once a `RequestSink` is instantiated, its `setupRouter` method is invoked. This method takes a `Router` that you must configure with all of the routes your application will respond to. (See [Routing](routing.md) for more details.)

When setting up routes, you will create many instances of `RequestController`. Any services these controllers need should be injected in their constructor. For example, `Authorizer`s need an instance of `AuthServer` to validate a request. The following code is an example of this:

```dart
class MySink extends RequestSink {
  MySink(ApplicationConfiguration config) : super(config) {  
    authServer = new AuthServer(...);
  }

  AuthServer authServer;

  @override
  void setupRouter(Router router) {
    router
        .route("/path")
        .pipe(new Authorizer(authServer))
        .listen((req) => new Response.ok("Authorized!"));
  }
}
```

This is the only time routes may be set up in an application, as the `Router` will restructure its registered routes into an optimized, immutable collection after this method is invoked.

You may not call any asynchronous functions in this this method.

After `setupRouter` has completed, the `RequestSink.router` property is set to the router this method configured.

### Perform Asynchronous Initialization with willOpen

For any initialization that needs to occur asynchronously, you may override `RequestSink.willOpen`. This method is asynchronous, and the application will wait for this method to complete before sending any HTTP requests to the request sink. In general, you should avoid using this method and read the later section on Lazy Services.

### Start Receiving Requests

Once an `RequestSink` sets up its routes and performs asynchronous initialization, the application will hook up the stream of HTTP requests to the `RequestSink` and data will start flowing. Just prior to this, one last method is invoked on `RequestSink`, `didOpen`. This method is a final callback to the `RequestSink` that indicates all initialization has completed.

## Lazy Services

An Aqueduct application will probably communicate to other servers and databases. A `RequestSink` will have properties to represent these connections. Services like these must open a persistent network connection, a process that is asynchronous by nature. Following the initialization process of a `RequestSink`, it may then make sense to create the services in a constructor and then open them in `willOpen`.

However, an Aqueduct application will run for a long time. It is probable that connections it uses will occasionally be interrupted. If these connections are only opened when the application first starts, the application will not be able to reopen these connections without restarting it. This would be catastrophic.

For that reason, asynchronous services should manage their own opening behavior. For example, a database connection should open it when it is asked to execute a query. If it has a valid connection, it will go ahead and execute the query. Otherwise, it will establish the connection and then execute the query. The caller doesn't care - they get a `Future` with the desired data.

The pseudo-code looks something like this:

```dart
Future execute(String sql) async {
  if (connection == null || !connection.isAvailable) {
    connection = new Connection(...);
    await connection.open();
  }

  return await connection.executeSQL(sql);
}
```

From the perspective of an `HTTPController`, it doesn't care about the underlying connection. It invokes `execute`, and the connection object figures out if it needs to establish a connection first:

```dart
@Bind.get()
Future<Response> getThings() async {
  // May or may not create a new connection, but will either return
  // some things or throw an error.
  var things = await connection.execute("select * from things");

  ...
}
```

## Multi-threaded Aqueduct Applications

Aqueduct applications can - and should - be spread across a number of threads. This allows an application to take advantage of multiple CPUs and serve requests faster. In Dart, threads are called *isolates* (and have some slight nuances to them that makes the different than a traditional thread). Spreading requests across isolates is an architectural tenet of Aqueduct applications.

When an application is started with `aqueduct serve`, a option indicates how many isolates the application should run on.

```
aqueduct serve --isolates 3
```

The number of isolates defaults to 3. An application will spawn that many isolates and create an instance of `RequestSink` for each. When an HTTP request is received, one of the isolates - and its `RequestSink` - will receive the request while the others will never see it. Each isolate works independently of each other, running as their own "web server" within a web server. Because a `RequestSink` initializes itself in the exact same way on each isolate, each isolate behaves exactly the same way.

An isolate can't share memory with another isolate. Therefore, each `RequestSink` instance has its own set of services, like database connections. This behavior also makes connection pooling implicit - the connections are effectively pooled by the fact that there is a pool of `RequestSink`s. If a `RequestSink` creates a database connection and an application is started with four isolates, there will be four database connections total.

However, there are times where you want your own pool or you want to share a single service across multiple isolates. For example, an API that must register with some other server (like in a system with an event bus) or must maintain a single persistent connection (like the error pipe to Apple's Push Notification Service or a streaming connection to Nest). These types of services should be instantiated in `initializeApplication`.

## The Application Object

Hidden in all of this discussion is the `Application<T>` object. Because the `aqueduct serve` command manages creating `Application<T>` instances, your code rarely concerns itself with this type.

An `Application<T>` is the top-level object in an Aqueduct application; it setups up HTTP listeners and sends their requests to `RequestSink` instances. The `Application<T>` itself is just a generic container for `RequestSink`s; it doesn't do much other than kick everything off.

The application's `start` method will initialize at least one instance of the application's `RequestSink`. If something goes wrong during this initialization process, the application will throw an exception and halt starting the server. For example, setting up an invalid route in a `RequestSink` subclass would trigger this type of startup exception.

An `Application<T>` has a number of options that determine how it will listen for HTTP requests, such as which port it is listening on or the SSL certificate it will use. These values are available in the application's `configuration` property, an instance of `ApplicationConfiguration`.

Properties of an `ApplicationConfiguration` and `Application<T>` are provided through the `aqueduct serve` command-line options.
