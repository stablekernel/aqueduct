# Understanding Application Initialization and the ApplicationChannel

Learn how an application is initialized so it can serve requests.

## Overview

Applications receive and fulfill HTTP requests using controllers. A *controller* is an object that can process a request in some way. In general, there are two types of processing and therefore two types of controllers:

- Middleware controllers ensure the request meets some criteria.
- Endpoint controllers fulfill a request.

Controllers are linked together - starting with middleware and ending with an endpoint controller - to form a series of steps a request will go through. These linked controllers are called the *application channel*. There is one application channel in an application.

A channel has an entry point - the first controller that will receive HTTP requests. If the request meets some criteria, the entry point will send the request to one of its linked controllers. This process continues until the request reaches a endpoint controller. When a request doesn't meet the conditions of a controller, the controller will remove it from the application channel and send a response. Removing a request from a channel will prevent any other controller from processing the request.

You subclass `ApplicationChannel` to define the channel for your application. Instances of your subclass are automatically created when an application starts.

### Building the ApplicationChannel

The only requirement of an Aqueduct application is that it has exactly one `ApplicationChannel` subclass. This subclass must provide an implementation for `entryPoint`. This method creates and links together the controllers that are your application channel. The controller returned from this method will be the first to receive requests. Here's an example:

```dart
class AppChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/users")
      .pipe(new Authorizer())
      .generate(() => new UserController());

    return router;
  }
}
```

This method creates four controllers, the first being a `Router` which is returned from this method and is therefore the first controller to receive requests. Each call to `route`, `pipe`, and `generate` creates a new controller and links it to the previous. The linked controllers in order are:

1. `Router`
2. `RouteController` (created internally by `route`; this class is opaque)
3. `Authorizer` (added with `pipe`)
4. `UserController` (added with `generate`)

In this example, a router will let requests with the path `/users` go to a `RouteController` created by `route`. This controller is very simple - it always forwards it to its next controller, here, an `Authorizer`. If the request is authorized, the `Authorizer` will let it pass to a `UserController`. The fictional `UserController` will fulfill the request.

The first three controllers are middleware and `UserController` is an endpoint controller. If the request path were not `/users`, the router would respond with 404 Not Found. The request would never get sent to the `RouteController`, nor any of the other controllers after it. If the request were not authorized - but the path was `/users` - the `Authorizer` would respond with 401 Unauthorized and the `UserController` will never see it.

!!! tip "route, pipe, generate and listen"
    There are four channel construction methods. They all create and link controllers together, but they have slightly different behavior. This behavior is covered in [this guide](controller.md).

## Providing Services for Controllers

Controllers often need to get (or create) information from outside the application. The most common example if information stored outside an application is a database, but it could be anything: another REST API, a connected device, etc. A *service object* encapsulates the information and behavior needed to work with an external system. Controllers use service objects to carry out their task. This separation of concerns between controllers and service objects allows for better structured and more testable code.

Service objects are passed to controllers through their constructor. A controller that needs a database connection, for example, would take a database connection object in its constructor and store it in a property. Services are created by overriding `prepare()` in an `ApplicationChannel`. Here's an example:

```dart
class AppChannel extends ApplicationChannel {
  PostgreSQLConnection database;

  @override
  Future prepare() async {
    database = new PostgreSQLConnection();
  }

  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/users")
      .pipe(new Authorizer())
      .generate(() => new UserController(database));

    return router;
  }
}
```

Notice that `database` is created in `prepare()`, stored in a property and passed to each new instance of `UserController`. The `prepare()` method is always executed before `entryPoint` is called.

## Channel Initialization

A benefit to using service objects is that they can be altered depending on the environment the application is running in without requiring changes to our controller code. For example, the database an application will connect to will be different when running in production than when running tests.

Besides service configuration, there may be other types of initialization an application wants to take. Common tasks include adding codecs to `HTTPCodecRepository` or setting the default `CORSPolicy`.

All of this initialization is done in `prepare()`.

Some of the information needed to configure an application will come from a configuration file or environment variables. This information is available through the `options` property of an application channel. For more information on using a configuration file and environment variables to guide initialization, see [this guide](configure.md).

## Multi-threaded Aqueduct Applications

Aqueduct applications can - and should - be spread across a number of threads. This allows an application to take advantage of multiple CPUs and serve requests faster. In Dart, threads are called *isolates*. An instance of your `ApplicationChannel` is created for each isolate. When your application receives an HTTP request, one of these instances receives the request and processes it. Since each application channel is an instance of the same type, these instances are replicas of one another and it doesn't matter which instance processes the request. This isolate-channel architecture is very similar to running multiple servers that run the same application.

The number of isolates an application will use is configurable at startup when using the [aqueduct serve](../cli/running.md) command.

An isolate can't share memory with another isolate. If an object is created on one isolate, it can be referenced by another. Therefore, each `ApplicationChannel` instance has its own set of services that are configured in the same way. This behavior also makes design patterns like connection pooling implicit; instead of a pool of database connections, there is a pool of application channels that each have their own database connection.

This architecture intentionally prevents you from keeping state in your application. When you scale to multiple servers, you can trust that your cluster works correctly because you are already effectively clustering on a single server node. For further reading on writing multi-threaded applications, see [this guide](threading.md).

## Initialization Callbacks

Both `prepare()` and `entryPoint` are part of the initialization process of an application channel. Most applications only ever need these two methods. Another method, that is rarely used, is `willStartReceivingRequests()`. This method is called after `prepare()` and `entryPoint` have been executed, and right before your application will start receiving requests.

These three initialization callbacks are called once per isolate to initialize the channel running on that isolate. For initialization that should only occur *once per application start* (regardless of how many isolates are running), an `ApplicationChannel` subclass can implement a static method named `initializeApplication()`.

### initializeApplication

For one-time, application-wide initialization tasks, you may add the following *static* method to your application channel subclass:

```dart
class AppChannel extends ApplicationChannel {
  static Future initializeApplication(ApplicationOptions config) async {
    ... do one time setup ...
  }

  ...
}
```

This method is invoked before any `ApplicationChannel` instances are created. Any changes made to `config` will be available in each `ApplicationChannel`'s `options` property.

For example:

```dart
class AppChannel extends ApplicationChannel {

  static Future initializeApplication(ApplicationOptions config) async {        
    config.context["special item"] = "xyz";
  }  

  Future prepare() async {
    var parsedConfigValues = options.context["special item"]; // == xyz
    ...
  }
}
```

It is important to note the behavior of isolates as it relates to Aqueduct and the initialization process. Each isolate has its own heap. `initializeApplication` is executed in the main isolate, whereas each `ApplicationChannel` is instantiated in its own isolate. This means that any values stored in `ApplicationOptions` must be safe to pass across isolates - i.e., they can't contain references to closures.

Additionally, any global variables or static properties that are set in the main isolate *will not be set* in other isolates. Configuration types like `HTTPCodecRepository` do not share values across isolates, because they use a static property to hold a reference to the repository of codecs. Therefore, they must be set up in `ApplicationChannel.prepare()`.

Also, because static methods cannot be overridden in Dart, it is important that you ensure the name and signature of `initializeApplication` exactly matches what is shown in these code samples. The analyzer can't help you here, unfortunately.

## Application Channel File

An `ApplicationChannel` subclass is most often declared in its own file named `lib/channel.dart`. This file must be exported from the application library file. For example, if the application is named `wildfire`, the application library file is `lib/wildfire.dart`. Here is a sample directory structure:

```
wildfire/
  lib/
    wildfire.dart
    channel.dart
    controllers/
      user_controller.dart      
    ...
```

See [this guide](structure.md) for more details on how an Aqueduct application's files are structured.

## Lazy Services

Many service objects will establish a persistent network connection. A network connection can sometimes be interrupted and have to re-establish itself. If these connections are only opened when the application first starts, the application will not be able to reopen these connections without restarting the application. This would be very bad.

For that reason, services should manage their own connectivity behavior. For example, a database connection should connect it when it is asked to execute a query. If it already has a valid connection, it will go ahead and execute the query. Otherwise, it will establish the connection and then execute the query. The caller doesn't care - it gets a `Future` with the desired result.

The pseudo-code looks something like this:

```dart
Future execute(String sql) async {
  if (connection == null || !connection.isAvailable) {
    connection = new Connection(...);
    await connection.open();
  }

  return connection.executeSQL(sql);
}
```

## The Application Object

Hidden in all of this discussion is the `Application<T>` object. Because the `aqueduct serve` command manages creating an `Application<T>` instance, your code rarely concerns itself with this type.

An `Application<T>` is the top-level object in an Aqueduct application; it sets up HTTP listeners and directs requests to `ApplicationChannel`s. The `Application<T>` itself is just a generic container for `ApplicationChannel`s; it doesn't do much other than kick everything off.

The application's `start` method will initialize at least one instance of the application's `ApplicationChannel`. If something goes wrong during this initialization process, the application will throw an exception and halt starting the server. For example, setting up an invalid route in a `ApplicationChannel` subclass would trigger this type of startup exception.

An `Application<T>` has a number of options that determine how it will listen for HTTP requests, such as which port it is listening on or the SSL certificate it will use. These values are available in the channel's `options` property, an instance of `ApplicationOptions`.
