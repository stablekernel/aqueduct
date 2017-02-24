---
layout: page
title: "Handling Requests"
category: http
date: 2016-06-19 21:22:35
order: 4
---

An Aqueduct application's job is to respond to HTTP requests. Each request in an Aqueduct application is an instance of `Request` (see [Request and Response Objects](request_and_response.html)). The behavior of processing and responding to requests is carried out by instances of `RequestController`.

A `RequestController` instance is an object that represents a functional unit in a request processing pipeline. A pipeline is composed of many `RequestController`s that are chained together. Each `RequestController` either validates, modifies or responds to a `Request`.

There are many subclasses of `RequestController` that perform different processing steps on a request. Some request controllers - like `HTTPController` - implement the business logic of handling a request. Others, like `Authorizer`, validate the authorization of a request. A `RequestController` can also be a simple closure, but is often subclasses to create reusable pipeline components.

## Request Streams and RequestController Listeners

Aqueduct applications use a reactive programming model to respond to HTTP requests. A reactive model mirrors a real life assembly line. In an assembly line of cars, the body of a car gets put on a conveyor belt. The first worker puts on a steering wheel, the next puts on tires and the last one paints the car a color. The car is then removed from the conveyor belt and sold. Each worker has a specific job in a specific order - they rely on the rest of the assembly line to complete the car, but their job is isolated. If a worker notices a defect in their area of expertise, they remove the car from the assembly line before it is finished and discard it.

A reactive application works the same way. An *event* is added to a *stream*, just like the body of the car gets put on a conveyor belt. A series of *event listeners* process the event by taking a specific operation in isolation. If an event listener rejects the event, the event is discarded and no more listeners receive it. Information can be added to the event as it passes through listeners. When the last listener finishes its job, the event is completed.

In Aqueduct, every HTTP request is an event and an instance of `Request`. Event listeners are instances of `RequestController`. When a request controller gets a request, it can choose to respond to it. This sends the HTTP response back to the client. Every `RequestController` may have a `nextController` property - a reference to another `RequestController`. A `RequestController` can choose *not* to respond to a request and pass the request to its `nextController`.

Controllers that pass a request on are commonly referred to as *middleware* or *interceptors* on other platforms. In Aqueduct, all `RequestControllers` are capable of being positioned at any point in a listener pipeline.

An example of middleware-like `RequestController` subclass is `Authorizer` - it validates the authorization of a request. An `Authorizer` will only allow a request to go to its `nextController` if the credentials are valid. Otherwise, it responds to the request with an authentication error - its `nextController` will never see it. Some `RequestController`s, like `Router`, have more than one `nextController`, allowing the stream of requests to be split based on some condition (see [Routing](routing.html) for more information).

An Aqueduct application, then, is a hierarchy of `RequestController`s that a request travels through to get responded to. In every Aqueduct application, there is a root `RequestController` that is first to receive every request. The specifics of that root controller are covered in [Request Sinks](request_sink.html); for now, we'll focus on the fundamentals of how `RequestController`s work together to form a series of steps to process a request.

Based on the previous description, you might envision a series of `RequestController`s being set up like so:

```dart
var c1 = new RequestController();
var c2 = new RequestController();
var c3 = new RequestController();

c1.nextController = c2;
c2.nextController = c3;
```

However, this is rather cumbersome code. Instead, the code to organize controllers is similar to how higher-ordered `List<T>` methods or `Stream<T>` methods are structured - like `map`, `fold` and `where`. All `RequestController`s have the following methods: `pipe`, `listen` and `generate`. Each of these methods sets the `nextController` of the receiver and returns that `nextController` so another one can be attached. A `Request` goes through those controllers in order.

```dart
var root = new RequestController();
root
  .listen((Request req) async => req)
  .pipe(new Authorizer())
  .generate(() => new ManagedObjectController<Account>());
```

In the above example, when a request is received by `root`, it flows through the next three `RequestController`s set up by `listen`, `pipe` and `generate`. Along the way, if any of those controllers respond to the request, the request is not delivered to the next controller in line.

All of these three methods set the `nextController` property of the receiver, but have a distinct usage.

`listen` is the most primitive of the three: it takes a closure that takes a `Request` and returns either a `Future<Request>` or `Future<Response>`. Behind the scenes, the `listen` closure is wrapped in an instance of `RequestController`.

While using a closure is a succinct way to describe a request processing step, you will often want to reuse the behavior of a controller across streams and organize your code into files. Instances of `RequestController` subclasses can be added to a series of controllers through `pipe` and `generate`. `pipe` takes an instance of a `RequestController` subclass. Each time a request makes it to this processing stage, the `pipe`d controller will process it and either respond or pass it along to the next controller.

`generate` is slightly different than `pipe`; `generate` creates a new instance of a `RequestController` each time a request makes it to that processing stage. The argument to `generate` must be a closure that returns an instance of a `RequestController` subclass, whereas `pipe` takes a single instance that will be reused for each request.

The generating behavior is useful for `RequestController` subclasses like `HTTPController`, which have properties that reference the `Request` it is processing. Since Aqueduct applications process `Request`s asynchronously and can service more than one `Request` at a time, a controller that has properties that change for every `Request` would run into a problem; while they are waiting for an asynchronous operation to complete, a new `Request` could come in and change their properties. When the asynchronous operation completes, the reference to the previous request is lost. This would be bad.

`RequestController` subclasses that have properties that change for every request must be added as a listener using `generate`. To prevent errors, subclasses like this have `@cannotBeReused` metadata. If you try to `pipe` to a controller with this metadata, you'll get an exception at startup and a helpful error message telling you to use `generate`.

## Subclassing RequestController

By default, a `RequestController` does nothing with a `Request` but forward it on to its `nextController`. To provide behavior, you must create a subclass and override `processRequest`.

```dart
class Controller extends RequestController {
  @override
  Future<RequestControllerEvent> processRequest(Request request) async {
      ... return either request or a new Response ...
  }
}
```

`RequestControllerEvent` is either a `Request` or a `Response`. Therefore, this method returns either a `Future<Request>` or `Future<Response>` - just like the closure passed to `listen`. In fact, a `RequestController` created by `listen` implements `processRequest` to simply invoke the provided closure.

The return value of `processRequest` dictates the control flow of a request stream - if it returns a request, the request is passed on to the `nextController`. The `nextController` will then invoke its `processRequest` and this continues until a controller returns a response. If no controller responds to a request, no response will be sent to the client. You should avoid this behavior.

A controller must return the same instance of `Request` it receives, but it may attach additional information by adding key-value pairs to the request's `attachments`.

An `HTTPController` - a commonly used subclass of `RequestController` - overrides `processRequest` to delegate processing to another method. The method chosen depends on the path variables of the `Request` and its HTTP method (see also [HTTPControllers](http_controller.html)). Subclasses of `RequestController` like `Authorizer` override `processRequest` to validate a request before it lets its `nextController` receive it. The pseudo-code of an `Authorizer` looks like this:

```dart
Future<RequestControllerEvent> processRequest(Request request) async {
    if (!isAuthorized(request)) {
      return new Response.unauthorized();
    }

    request.attachments["authInfo"] = authInfoFromRequest(request);
    return request;
}
```

In other words, the `processRequest` method is where controller-specific logic goes. However, you never call this method directly; it is a callback for when a request controller decides it is time to process a request. A `RequestController` receives requests through its `receive` method. This entry point sets up a try-catch block and invokes `processRequest`, gathering its result to determine the next course of action - whether to pass it on to the next controller or respond. You do not call `receive` directly, `RequestController`s already know how to use this method to send requests to their `nextController`.

When a `RequestController` returns `Response` from `processRequest`, the request is responded to and then discarded. No further `RequestController`s will receive the request. A `RequestController` also logs some of the details of the request after the response is sent.

Exceptions thrown in `processRequest` bubble up to the try-catch block in `receive`. Therefore, you typically don't have to do any explicit exception handling code in your request processing code. The benefit here is cleaner code, but also if you fail to catch an exception, the request will still get responded to. When an exception is thrown from within `processRequest`, your request processing code is terminated, an appropriate response is sent and no subsequent controllers are sent the request. (The details of how an exception maps to a response are in a later section.) If you don't want a particular exception to use this behavior, you can catch it and take your own action.

Prior to invoking `processRequest`, the implementation of `receive` will determine if the request is a CORS request and perhaps take a different action. See a later section for details on handling CORS requests.

Classes like `Router`, which have more than one "next controller", override `receive` instead of `processRequest`. In general, you want to avoid overriding `receive`, because so much of its behavior is required for Aqueduct to behave properly.

## Exception Handling

If an exception is thrown while processing a request, it will be caught by the `RequestController` doing the processing. The controller will respond to the HTTP request with an appropriate status code and no subsequent controllers will receive the request.

There are two types of exceptions that a `RequestController` will interpret to return a meaningful status code: `HTTPResponseException` and `QueryException`. Any other uncaught exceptions will result in a 500 status code error.

`QueryException`s are generated by the Aqueduct ORM. A request controller interprets these types of exceptions to return a suitable status code. The following reasons for the exception generate the following status codes:

|Reason|Status Code|
|---|---|
|A programmer error (bad query syntax)|500|
|Unique constraint violated|409|
|Invalid input|400|
|Database can't be reached|503|

An `HTTPResponseException` can be thrown at anytime to escape early from processing and return a response. Exceptions of these type allow you to specify the status code and a message. The message is encoded in a JSON object for the key "error". Some classes in Aqueduct will throw an exception of this kind if some precondition isn't met. You may add your own try-catch blocks to request processing code to either catch and reinterpret the behavior of `HTTPResponseException` and `QueryException`, or for any other reason.

Other than `HTTPResponseException`s, exceptions are always logged along with some details of the request that generated the exception. `HTTPResponseException`s are not logged, as they are used for control flow and are considered "normal" operation.
