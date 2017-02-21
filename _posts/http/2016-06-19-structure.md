---
layout: page
title: "Aqueduct Application Structure"
category: http
date: 2016-06-19 21:22:35
order: 2
---

An Aqueduct application is a tree of `RequestController`s. A `RequestController` takes a `Request` and either creates a `Response` or passes the `Request` to another `RequestController`. More often than not, `RequestController` is subclassed to create reusable components to build a request processing pipeline. Some commonly used `RequestController`s are `RequestSink`, `Authorizer`, `Router` and `HTTPController`.

Every application has one `RequestSink` subclass. Instances of this subclass are the first `RequestController` to receive a new request. See [Request Sink](request_sink.html) for more details. Here's an example of a basic `RequestSink` subclass:

```dart
class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config);

  @override
  void setupRouter(Router router) {
    router
      .route("/users/[:id]")
      .pipe(new Authorizer(authServer))
      .generate(() => new UserController);

    router
      .route("/index")
      .pipe(new StaticPageController("index.html"));
  }
}
```

A `RequestSink` immediately sends a `Request` to its `Router`. A `Router` inspects the path of the request and sends it to another `RequestController` that has been registered to handle requests of that path. A `Router` can group paths together so that they all go the same controller. A typical route is `/users/[:id]` - which matches paths like `/users` and `/users/1`. Routes are registered by overriding `setupRouter()` in the application's `RequestSink` subclass.

See [Routing](routing.html) for more details.

After a request is split

The mechanism by which these `Request`s are created and sent to `RequestSink` are internal - just by creating a `RequestSink` subclass, requests can be received.

`RequestSink`s also sets up the flow of the application's `RequestController`s and initializes things like database connections. By convention, a `RequestSink` subclass is in its own file named `lib/<application_name>_request_sink.dart`. This file must visible to the application library file. (In an application named `foo`, the library file is `lib/foo.dart`.) An example directory structure:

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

A `RequestSink` has a `Router`. A `Router` registers `RequestController`s with string patterns called *routes*. When a new `Request` is sent to a `RequestSink`, it is immediately sent to the sink's `router`.
