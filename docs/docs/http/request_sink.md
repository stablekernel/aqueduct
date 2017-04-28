# Application Initialization and the RequestSink

The only requirement of an Aqueduct application is that it has exactly one `RequestSink` subclass. This subclass handles the initialization of an application, including setting up routes, authorization and database connections.

By convention, a `RequestSink` subclass is declared in its own file named `lib/<application_name>_request_sink.dart`. This file must visible to the application library file. (In an application named `foo`, the library file is `lib/foo.dart`.) An example directory structure:

```
wildfire/
  lib/
    wildfire.dart
    wildfire_request_sink.dart
    controllers/
      user_controller.dart      
    ...
```

To make the `RequestSink` subclass visible, the file `wildfire.dart` imports `wildfire_request_sink.dart`:

```dart
import 'wildfire_request_sink.dart';
```

Applications are run with the command line tool `aqueduct serve`. This tool finds the subclass of `RequestSink` visible to the application library file.

An Aqueduct application will create multiple instances of a `RequestSink` subclass. Each instance has its own `Isolate` - Dart's version of a thread - that it will process requests on. This behavior allows an application's code to be replicated across a number of threads.

## Subclassing RequestSink

The responsibility of a `RequestSink` is to set up routes and initialize resources it will use to fulfill requests. There are five initialization methods in `RequestSink`, each with its own purpose. The methods and the order they are executed in are as follows:

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

A common use of this method is to set up resources that will be shared across isolates or unique persistent connections to remote services. This method can modify `ApplicationConfiguration` prior to `RequestSink` instances being created. This allows resources allocated during this one-time setup method can be accessible by each `RequestSink` instance.

In its simplest form, `initializeApplication` will often read values from a [configuration file](configure.md) and set them in the `ApplicationConfiguration.options` map. That looks like this:

```dart
static Future initializeApplication(ApplicationConfiguration config) async {        
  config.options["Configuration Values"] = new Configuration(config.configurationFilePath);;
}  

RequestSink(ApplicationConfiguration config) {
  var parsedConfigValues = config.options["Configuration Values"];
}
```

In a more complex example, Aqueduct applications that use [scribe](https://pub.dartlang.org/packages/scribe) will implement `initializeApplication` to optimize logging. `scribe` works by spawning a new isolate that writes log statements to disk or the console. Other isolates that do work send their log messages to `scribe`'s logging isolate so that they can move on to more important things. The logging isolate is spawned in `initializeApplication`, and a communication port to that isolate is added to the `ApplicationConfiguration`. Each `RequestSink` grabs that communication port so that it can send messages to the logging isolate later.

It is important to note the behavior of isolates as it relates to Aqueduct and the initialization process. Each isolate has its own heap. `initializeApplication` is executed in the main isolate, whereas each `RequestSink` is instantiated in its own isolate. This means that any values stored in `ApplicationConfiguration` must be safe to pass across isolates - i.e., they can't contain references to closures.

Additionally, any static or global variables that are set in the main isolate *will not be set* in other isolates. Static properties like the encoder and decoder maps created by `Response.addEncoder` and `HTTPBody.addDecoder` must not be modified in `initializeApplication`, since these changes will not occur in other isolates. For initialization that is isolate-specific, see later sections.

Also, because static methods cannot be overridden in Dart, it is important that you ensure the name and signature of `initializeApplication` exactly matches what is shown in these code samples. The analyzer can't help you here, unfortunately.

### Use RequestSink's Constructor to Initialize Resources and Isolate-Specific Configurations

A resource, in this context, is something your application will use to fulfill requests. A database connection is an example of a resource. Resources should be created the constructor of a `RequestSink` and stored as properties.

The constructor of a `RequestSink` must be unnamed and take a single argument of type `ApplicationConfiguration`. This instance of `ApplicationConfiguration` will have the same values as the instance in the previous initialization step (`initializeApplication`) and will retain any values this step applied to the configuration. The values in `ApplicationConfiguration` often contain the details for the resources that should be created - like database connection information. Here is an example:

```dart
class MySink extends RequestSink {
  MySink(ApplicationConfiguration config) : super(config) {
    var databaseConnectionInfo = config["Database Connection Info"];
    var databaseConnection = new DatabaseConnection()
      ..connectionInfo = databaseConnectionInfo;
  }
}
```

Isolate specific initialization should also be set in this method.

```dart
class MySink extends RequestSink {
  MySink(ApplicationConfiguration config) : super(config) {
    Response.addEncoder(new ContentType("application", "xml"), xmlEncoder);
  }
}  
```

All of the properties of a `RequestSink` should be initialized in its constructor. This allows the next phase of initialization - setting up routes - to inject these resources into controllers. For example, a typical `RequestSink` will have some property that holds a database connection; this property should be initialized in the constructor.

A constructor for a `RequestSink` may look like this:

```dart
class WildfireSink extends RequestSink {
  static String ConfigurationKey = "config";

  static Future initializeApplication(ApplicationConfiguration config) async {        
    config.options[ConfigurationKey] = new Configuration(config.configurationFilePath);
  }  

  WildfireSink(Map<String, dynamic> opts) : super(opts) {
    WildfireConfiguration configuration = opts[ConfigurationKey];

    context = contextWithConnectionInfo(configuration.database);

    authServer = new AuthServer<User, Token, AuthCode>(new WildfireAuthDelegate());
  }

  ManagedContext context;
  AuthServer authServer;
}
```

A constructor should never call asynchronous functions. Some resources require asynchronous initialization - e.g., a database connection has to connect to a database - but those must be fully initialized later. (See a later section on Lazy Resources.)

### Setting up Routes in setupRouter

Once a `RequestSink` is instantiated, its `setupRouter` method is invoked. This method takes a `Router` that you must configure with all of the routes your application will respond to. (See [Routing](routing.md) for more details.)

When setting up routes, you will create many instances of `RequestController`. Any resources these controllers need should be injected in their constructor. For example, `Authorizer`s need an instance of `AuthServer` to validate a request. The following code is an example of this:

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

You may not call any asynchronous functions in this this method and you should not alter the state of any properties.

After `setupRouter` has completed, the `RequestSink.router` property is set to the router this method configured.

### Perform Asynchronous Initialization with willOpen

For any initialization that needs to occur asynchronously, you may override `RequestSink.willOpen`. This method is asynchronous, and the application will wait for this method to complete before sending any HTTP requests to the request sink. In general, you should avoid using this method and read the later section on Lazy Resources.

### Start Receiving Requests

Once an `RequestSink` sets up its routes and performs asynchronous initialization, the application will hook up the stream of HTTP requests to the `RequestSink` and data will start flowing. Just prior to this, one last method is invoked on `RequestSink`, `didOpen`. This method is a final callback to the `RequestSink` that indicates all initialization has completed.

## Lazy Resources

An Aqueduct application will probably communicate to other servers and databases. A `RequestSink` will have properties to represent these connections. Resources like these must open a persistent network connection, a process that is asynchronous by nature. Following the initialization process of a `RequestSink`, it may then make sense to create the resources in a constructor and then open them in `willOpen`. And while this could be true, resources like this should manage the opening and closing of their underlying network connection internally.

For example, an object that has a database connection should open it when it goes to execute a query, but doesn't have a valid connection. This is how `PersistentStore`s work - they store properties that have all of the information they need to connect to a database when initialized, but do not immediately open a connection. The first time the `PersistentStore` has to fulfill a query, it executes a function that opens the database connection. This defers fully loading the resource until it is needed, but there is actually a much more important behavior here.

An Aqueduct application (ideally) will run for a long time. During that time, the servers and databases it connects to may not always be reachable - perhaps they went down to be upgraded or there was an outage of some kind. An Aqueduct application must be able to recover from this. If opening an external connection only happened during startup, an application would not reopen a connection if it went down for some reason. This would be bad.

In the general case, a resource of this nature will have methods that use the underlying connection. These methods must be responsible for ensuring the underlying connection is valid and reopen it (or report failure) if that is not the case. For example, a simple database connection class might implement its `execute` method like so:

```dart
Future execute(String sql) async {
  if (connection == null || !connection.isAvailable) {
    connection = new Connection(...);
    await connection.open();
  }

  return await connection.executeSQL(sql);
}
```

From the perspective of a `RequestController`, it doesn't care about the underlying connection. It invokes `execute`, and the connection object figures out if it needs to establish a connection first:

```dart
@httpGet getThings() async {
  // May or may not create a new connection, but will either return
  // some things or throw an error.
  var things = await connection.execute("select * from things");

  ...
}
```

## Multi-threaded Aqueduct Applications

Aqueduct applications can - and should - be spread across a number of threads. This allows an application to take advantage of multiple CPUs and serve requests faster. In Dart, threads are called *isolates* (and have some slight nuances to them that makes the different than a traditional thread). Spreading requests across isolates is an architectural tenet of Aqueduct applications.

When an application is started with `aqueduct serve`, a flag indicates how many isolates the application should run on. This defaults to 3. An application will spawn that many isolates and create an instance of `RequestSink` for each. When an HTTP request is received, one of the isolates - and its `RequestSink` - will receive the request while the others will never see it. Each isolate works independently of each other, running as their own "web server" within a web server. Because a `RequestSink` initializes itself in the exact same way on each isolate, each isolate behaves exactly the same way.

An isolate can't share memory with another isolate. Therefore, each `RequestSink` instance has its own set of resources, like database connections. This behavior also makes connection pooling a non-issue - the connections are effectively pooled by the fact that there is a pool of `RequestSink`s. If a `RequestSink` creates a database connection and an application is started with four isolates, there will be four database connections total.

However, there are times where you want your own pool or you want to share a single resource across multiple isolates. For example, an API that must register with some other server (like in a system with an event bus) or must maintain a single persistent connection (like the error pipe to Apple's Push Notification Service or a streaming connection to Nest). These types of resources should be instantiated in `initializeApplication`.

## Preprocessing Requests and initialHandler

By default, when a `RequestSink` receives an HTTP request, it immediately forwards it to its `router`. However, if an application wishes to take some action prior to routing, use another router or forego routing altogether, the `Router` can be skipped. Every `RequestSink` has an `initialHandler` property that it forwards all requests to. This property defaults to the request sink's `router`, but can be overridden to return something else.

If you only wish to preprocess a request, you may instead override `RequestSink.willReceiveRequest`. This asynchronous method takes the incoming `Request` as an argument, but can't respond to it.

## The Application Object

Hidden in all of this discussion is the `Application<T>` object. Because the `aqueduct serve` command manages creating `Application<T>` instances, your code rarely concerns itself with this type.

An `Application<T>` is the top-level object in an Aqueduct application; it setups up HTTP listeners and channels their requests to `RequestSink` instances. The `Application<T>` itself is just a generic container for `RequestSink`s; it doesn't do much other than kick everything off.

The application's `start` method will initialize at least one instance of the application's `RequestSink`. If something goes wrong during this initialization process, the application will throw an exception and halt starting the server. For example, setting up an invalid route in a `RequestSink` subclass would trigger this type of startup exception.

An `Application<T>` has a number of options that determine how it will listen for HTTP requests, such as which port it is listening on or the SSL certificate it will use. These values are available in the application's `configuration` property, an instance of `ApplicationConfiguration`.

An application will likely have other kinds of configurable options that are specific to the application, like connection information for a database. For this purpose, `ApplicationConfiguration` has a `options` property - a `Map` - that takes dynamic data. This type of information usually comes from a configuration file or environment variables. This information is simply forwarded to every `RequestSink` during their initialization.

Properties of an `ApplicationConfiguration` and `Application<T>` are provided through the `aqueduct serve` command.
