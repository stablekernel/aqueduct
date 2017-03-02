# Aqueduct Application Structure

An Aqueduct application created with the command-line tool `aqueduct create` will create an application with the structure discussed in this document. See [Getting Started](../index.md#getting-started) for installation and usage.

An Aqueduct application is a tree of `RequestController`s. A `RequestController` takes a `Request` and either creates a `Response` or passes the `Request` to another `RequestController` in the tree. More often than not, `RequestController` is subclassed to create reusable components to build a request processing pipeline. Some commonly used `RequestController`s are `RequestSink`, `Authorizer`, `Router` and `HTTPController`.

The root of the `RequestController` tree is always an application-specific subclass of `RequestSink`. The only requirement of an Aqueduct application is that a subclass of this type is declared in an application package and is visible from its top-level library file. A `RequestSink` is not only the first `RequestController` that receives requests, its initialization process creates all of the other `RequestController`s in an application. See [Request Sink](request_sink.md) for more details.

A `RequestSink` sends all `Request`s to its `Router`. A `Router` figures out which `RequestController` to send a `Request` to based on the HTTP request path. Setting up which `RequestController` receives requests for a particular path (or paths) is called routing. Routing is done by overriding `RequestSink`'s `setupRouter` method. If no `RequestController` has matches the path of the request, the `Router` responds with a 404 and dumps the request. See [Routing](routing.md) for more details.

Once past a router, a `Request` typically goes through an `Authorizer` then an `HTTPController` subclass. An `Authorizer` validates the Authorization header of a request, and attaches authorization information to the request so that the next controller can use it. If an `Authorizer` rejects a request, it responds to it with a 401 and does not pass it to the next controller. See [Authorization](../auth/overview.md) for more details.

An `HTTPController` subclass handles all of the operations for an HTTP resource collection (or single resource in that collection). For example, a subclass of `HTTPController` named `UserController` would likely be able to list users, show a single user, create a new user, delete a user or update an existing user. An `HTTPController` always responds to any request it receives. See [HTTPControllers](http_controller.md) for more details.

## Filesystem Structure

The directory structure of an Aqueduct application typically looks like this:

```
application_name/
  application_name.dart
  application_name_request_sink.dart
  controllers/
    user_controller.dart
```

Aqueduct applications are run by running `aqueduct serve` in project directory (here, `application_name`). The top-level library file, `application_name/application_name.dart`, must at least import `application_name_request_sink.dart` so that `aqueduct` serve can see it. See [Deploying](../deploy/overview.md) for more details on this command.
