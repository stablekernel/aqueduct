# Handling Requests: Fundamentals

Learn how `Controller` objects are linked together to handle HTTP requests.

## Overview

A controller is the basic building block of an Aqueduct application. A controller handles an HTTP request in some way. For example, a controller could return a 200 OK response with a JSON-encoded list of city names. A controller could also check a request to make sure it had the right credentials in its authorization header.

Controllers are linked together to compose their behaviors into a *channel*. A channel handles a request by performing each of its controllers' behavior in order. For example, a channel with the aforementioned controllers would verify the credentials of a request and then returning a list of city names.

![Aqueduct Channel](../img/simple_controller_diagram.png)

The `Controller` class provides the behavior for linking controllers together, and you subclass it to provide the logic for a particular controller behavior.

## Linking Controllers

Controllers are linked with their `link` method. This method takes a closure that returns the next controller in the channel. The following shows a channel composed of two  controllers:

```dart
final controllerA = new Controller();
controller.link(() => new Controller());
```

When `controllerA` handles a request, it can choose to respond to the request or let the request continue in the channel. When the request continues in this channel, the closure provided to `link` is invoked. The controller returned from this closure then handles the request. Any number of controllers can be linked together in a channel, but the last controller must respond to the request. These types of controllers are called *endpoint controllers*, as opposed to *middleware controllers* that verify or modify the request and let the next controller in the channel handle it.

Linking occurs in an [application channel](channel.md), and is finalized during startup of your application (i.e., once you have set up your controllers, the cannot be changed once the application starts receiving requests). In a typical application, a `Router` controller splits an application channel into multiple sub-channels.

### Why Closures?

It is important to understand why `link` takes a closure, instead of a controller instance. Aqueduct is an object oriented framework. Objects have both state and behavior. An application will receive multiple requests that will be handled by the same type of controller. If the same object were reused to handle multiple requests, it could retain some of its state between requests. This would create problems that are difficult to debug. By requiring closures, you are able to create a new instance for each request.

There are some types of controllers where you may want to reuse the same instance for each request. These controllers must not have any properties that change after they are added to a channel. To link these types of controllers, you instantiate them outside of the closure:

```dart
final controllerA = new Controller();
final controllerB = new Controller();
controllerA.link(() => controllerB);
```

You must not reuse a controller instance in multiple channels, because controllers keep a reference to the next controller in a channel. For example, the following code would not work because the link from A -> B would be overwritten and the only remaining channel would be A -> C.

```dart
final controllerA = new Controller();
final controllerB = new Controller();
final controllerC = new Controller();

controllerA.link(() => controllerB);
controllerA.link(() => controllerC);
```


## Creating Request Handling Behavior by Subclassing Controller

Every `Controller` implements its `handle` method to handle a request. You override this method in your controllers to provide the logic for your application's controllers. The following is an example of an endpoint controller, because it always sends a response:


```dart
class NoteController extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    final notes = await fetchNotesFromDatabase();

    return new Response.ok(notes);
  }
}
```

This `handle` method creates and returns a `Response` object. When a `handle` method returns a response, that response is sent to the client. Any linked controllers do not have their `handle` method invoked; the request is removed from the channel.

A middleware controller returns a response when the request is invalid. For example, an `Authorizer` controller returns a `401 Unauthorized` response if the request's credentials are invalid (this removes the request from the channel). If a middleware controller deems the request acceptable, it returns the request from its `handle` method. This signals to Aqueduct that the next controller in the channel should handle the request.

As an example, the pseudo-code for an `Authorizer` looks like this:

```dart
class Authorizer extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    if (isValid(request)) {
      return request;
    }

    return new Response.unauthorized();
  }
}
```

!!! tip "Endpoint Controllers"
    In most cases, endpoint controllers are created by subclassing [ResourceController](resource_controller.md). This controller allows you to declare more than one handler method in a controller to better organize logic. For example, one method might handle POST requests, while another handles GET requests.

### Modifying a Response with Middleware

A middleware controller can add a *response modifier* to a request. When an endpoint controller eventually creates a response, these modifiers are applied to the response before it is sent. Modifiers are added by invoking `addResponseModifier` on a request.

```dart
class Versioner extends Controller {
  Future<RequestOrResponse> handle(Request request) async {
    request.addResponseModifier((response) {
      response.headers["x-api-version"] = "2.1";
    });

    return request;
  }
}
```

Any number of controllers can add a response modifier to a request; they will be processed in the order that they were added. Response modifiers are applied before the response body is encoded, allowing the body object to be manipulated.

## Linking Functions

For simple behavior, functions with the same signature as `handle` can be linked to controllers:

```dart
  router
    .route("/path")
    .linkFunction((req) async => req);
    .linkFunction((req) async => new Response.ok(null));
```

Linking a function has all of the same behavior as `Controller.handle`: it can return a request or response, automatically handles exceptions, and can have controllers (and functions) linked to it.

## Exception Handling

If an exception or error is thrown during the handling of a request, the controller currently handling the request will catch it. For the majority of values caught, a controller will send a 500 Server Response. The details of the exception or error will be [logged](configure.md), and the request is removed from the channel (it will not be passed to a linked controller).

This is the default behavior for all thrown values except `Response` and `HandlerException`.

### Throwing Responses

A `Response` can be thrown at any time; the controller handling the request will catch it and send it to the client. This completes the request. This might not seem useful, for example, the following shows a silly use of this behavior:

```dart
class Thrower extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    if (!isForbidden(request)) {
      throw new Response.forbidden();
    }

    return new Response.ok(null);
  }
}
```

However, it can be valuable to send error responses from elsewhere in code as an application's codebase becomes more layered.

### Throwing HandlerExceptions

Exceptions can implement `HandlerException` to provide a response other than the default when thrown. For example, an application that handles bank transactions might declare an exception for invalid withdrawals:

```dart
enum WithdrawalProblem {
  insufficientFunds,
  bankClosed
}
class WithdrawalException implements Exception {
  AccountException(this.problem);

  final WithdrawalProblem problem;
}
```

Controller code can catch this exception to return a different status code depending on the exact problem with a withdrawal. If this code has to be written in multiple places, it is useful for `WithdrawalException` to implement `HandlerException`. An implementor must provide an implementation for `response`:

```dart
class WithdrawalException implements HandlerException {
  AccountException(this.problem);

  final WithdrawalProblem problem;

  @override
  Response get response {
    switch (problem) {
      case WithdrawalProblem.insufficientFunds:
        return new Response.badRequest(body: {"error": "insufficient_funds"});
      case WithdrawalProblem.bankClosed:
        return new Response.badRequest(body: {"error": "bank_closed"});
    }
  }
}
```

The Aqueduct ORM exceptions (`QueryException`) implement `HandlerException` to return a response that best represents the ORM exception. For example, if a unique constraint is violated by a query, the thrown exception implements `response` to return a 409 Conflict response.

## CORS Headers and Preflight Requests

`Controller`s have built-in behavior for handling CORS requests. They will automatically respond to `OPTIONS` preflight requests and attach CORS headers to any other response. See [the chapter on CORS](configure.md) for more details.
