# Understanding Application Initialization and the ApplicationChannel

Learn how an application is initialized so it can serve requests.

## Overview

Applications fulfill HTTP requests using [controllers](controller.md). A controller is an object that can handle a request in some way. In general, there are two types of controllers:

- Endpoint controllers fulfill a request (e.g., insert a row into a database and send a 200 OK response).
- Middleware controllers verify something about a request (e.g., verifying the Authorization header has valid credentials) or modify the response created by an endpoint controller (e.g., add a response header).

Controllers are linked together - starting with zero or more middleware and ending with an endpoint controller - to form a series of steps a request will go through. Every controller can either pass the request on to its linked controller, or respond to the request itself (in which case, the linked controller never sees the request). For example, an authorizer middleware will let a request pass if it has valid credentials, but will respond with a 401 Unauthorized response if the credentials are invalid. Some controllers, like `Router`, can have multiple controllers linked to it.

These linked controllers are called *channels*. You create and link channels in a subclass of `ApplicationChannel`. There is one `ApplicationChannel` subclass per application.

### Building the ApplicationChannel

You must override `ApplicationChannel.entryPoint` to return the first controller of your application's channel. In the implementation of this method, every controller that will be used in the application is linked to either the entry point in some way. Here's an example:

```dart
class AppChannel extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();

    router
      .route("/users")
      .link(() => Authorizer())
      .link(() => UserController());

    return router;
  }
}
```

This method links together a `Router`, `Authorizer` and `UserController` in that order. A request is first handled by the `Router`, and if its path matches '/users', it will be sent to an `Authorizer`. If the `Authorizer` verifies the request, the request is passed to a `UserController` for fulfillment.

By contrast, if the request's path doesn't match '/users', the `Router` sends a 404 Not Found response and doesn't pass it to the `Authorizer`. Likewise, if the request isn't authorized, the `Authorizer` will send a 401 Unauthorized response and prevent it from being passed to the `UserController`. In other words, a request 'falls out' of the channel once a controller responds to it, so that no further controllers will receive it.

!!! note "Linking Controllers"
    The `link()` method takes a closure that creates a new controller. Some controllers get instantiated for each request, and others get reused for every request. See [the chapter on controllers](controller.md) for more information.

## Providing Services for Controllers

Controllers often need to get (or create) information from outside the application. The most common example is database access, but it could be anything: another REST API, a connected device, etc. A *service object* encapsulates the information and behavior needed to work with an external system. This separation of concerns between controllers and service objects allows for better structured and more testable code.

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
      .link(() => new Authorizer())
      .link(() => new UserController(database));

    return router;
  }
}
```

Notice that `database` is created in `prepare()`, stored in a property and passed to each new instance of `UserController`. The `prepare()` method is always executed before `entryPoint` is called.

## Application Channel Configuration

A benefit to using service objects is that they can be altered depending on the environment the application is running in without requiring changes to our controller code. For example, the database an application will connect to will be different when running in production than when running tests.

Besides service configuration, there may be other types of initialization an application wants to take. Common tasks include adding codecs to `CodecRegistry` or setting the default `CORSPolicy`.

All of this initialization is done in `prepare()`.

Some of the information needed to configure an application will come from a configuration file or environment variables. This information is available through the `options` property of an application channel. For more information on using a configuration file and environment variables to guide initialization, see [this guide](configure.md).

## Multi-threaded Aqueduct Applications

Aqueduct applications can - and should - be spread across a number of threads. This allows an application to take advantage of multiple CPUs and serve requests faster. In Dart, threads are called *isolates*. An instance of your `ApplicationChannel` is created for each isolate. When your application receives an HTTP request, one of these instances receives the request and processes it. These instances are replicas of one another and it doesn't matter which instance processes the request. This isolate-channel architecture is very similar to running multiple servers that run the same application.

The number of isolates an application will use is configurable at startup when using the [aqueduct serve](../cli/running.md) command.

An isolate can't share memory with another isolate. If an object is created on one isolate, it *cannot* be referenced by another. Therefore, each `ApplicationChannel` instance has its own set of services that are configured in the same way. This behavior also makes design patterns like connection pooling implicit; instead of a pool of database connections, there is a pool of application channels that each have their own database connection.

This architecture intentionally prevents you from keeping state in your application. When you scale to multiple servers, you can trust that your cluster works correctly because you are already effectively clustering on a single server node. For further reading on writing multi-threaded applications, see [this guide](threading.md).

## Initialization Callbacks

Both `prepare()` and `entryPoint` are part of the initialization process of an application channel. Most applications only ever need these two methods. Another method, that is rarely used, is `willStartReceivingRequests()`. This method is called after `prepare()` and `entryPoint` have been executed, and right before your application will start receiving requests.

These three initialization callbacks are called once per isolate to initialize the channel running on that isolate. For initialization that should only occur *once per application start* (regardless of how many isolates are running), an `ApplicationChannel` subclass can implement a static method named `initializeApplication()`.

```dart
class AppChannel extends ApplicationChannel {
  static Future initializeApplication(ApplicationOptions options) async {
    ... do one time setup ...
  }

  ...
}
```

This method is invoked before any `ApplicationChannel` instances are created. Any changes made to `options` will be available in each `ApplicationChannel`'s `options` property.

For example:

```dart
class AppChannel extends ApplicationChannel {

  static Future initializeApplication(ApplicationOptions options) async {        
    options.context["special item"] = "xyz";
  }  

  Future prepare() async {
    var parsedConfigValues = options.context["special item"]; // == xyz
    ...
  }
}
```

It is important to note the behavior of isolates as it relates to Aqueduct and the initialization process. Each isolate has its own heap. `initializeApplication` is executed in the main isolate, whereas each `ApplicationChannel` is instantiated in its own isolate. This means that any values stored in `ApplicationOptions` must be safe to pass across isolates - i.e., they can't contain references to closures.

Additionally, any global variables or static properties that are set in the main isolate *will not be set* in other isolates. Configuration types like `CodecRegistry` do not share values across isolates, because they use a static property to hold a reference to the repository of codecs. Therefore, they must be set up in `ApplicationChannel.prepare()`.

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
