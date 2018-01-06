# Handling Requests: Fundamentals

Learn how `Controller` objects are linked together to handle HTTP requests.

## Overview

A controller is the basic building block of an Aqueduct application. A controller does something with an HTTP request. For example, a controller could return a 200 OK response with a JSON-encoded list of city names. A controller could also check a request to make sure it had the right username and password.

These controllers can be linked together to get more complex behavior: if the request has the right username and password, the response with city names is sent. Aqueduct applications are many linked together controllers that form an application's behavior. Some of these controllers are created specifically for an application, and some can be reused across multiple applications.

This ordered organization of controllers is called an *application channel*, and is created when the application starts. One controller is designated as the first controller in the channel. It is the channel's *entry point* and it the first to receive a new request. It can either send a response, or send it to its linked controller. The linked controller can do the same, and so on.

![Aqueduct Structure](../img/simple_controller_diagram.png)

Some controllers can choose from multiple controllers, depending on something about the request. In most applications, the entry point is a `Router` controller that chooses the next controller based on the path of the request.

![Aqueduct Structure](../img/simple_controller_diagram.png)

## Linking Controllers

Controllers are linked together by overriding the `entryPoint` getter of an `ApplicationChannel` subclass. Here's an example:

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/path")    
    .link(() => new Authorizer())
    .link(() => new NoteController());

  return router;
}
```

The `Router` controller returned from this getter is the entry point of the channel. It handles every request; if that request is '/path', a new `Authorizer` is created to handle the request next. The `Authorizer` makes sure the request is authorized before it reaches a `NoteController`. The `NoteController` fulfills the request - probably by sending a response with a list of notes or by adding a note from the request body to the database.

Linking controllers and creating an `ApplicationChannel` is covered more in depth in [this guide](channel.md).

## Creating Request Handling Behavior by Subclassing Controller

Controllers like `Router` and `Authorizer` are part of Aqueduct can be used in any application. Controllers that are specific to your application are defined by subclassing `Controller`. A controller's behavior is defined by overriding its `handle` method:

```dart
class NoteController extends Controller {
  @override
  Future<RequestOrResponse> handle(Request request) async {
    final notes = await fetchNotesFromDatabase();

    return new Response.ok(notes);
  }
}
```

This `handle` method always creates and returns a `Response` object. The response returned from a controller is sent to the client. A controller that always returns a response is called an *endpoint controller*. When linking a series of controllers, an endpoint controller is always the last link.

Controllers that handle the request before it reaches an endpoint controller are called *middleware controllers*. A typical middleware controller is `Authorizer` - it lets a request pass through if it has valid credentials in its Authorization header. An `Authorizer` sends an error response if the credentials aren't valid, preventing the endpoint from being reached. The pseudo-code for an `Authorizer` looks like this:

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

Controllers let a request pass to their linked controller by returning the request from `handle`. (Whereas returning a `Response` sends the response, and the linked controller never sees the request.)

!!! tip "Endpoint Controllers"
    In most cases, endpoint controllers are created by subclassing [RESTController](rest_controller.md). This controller allows you to declare more than one handler method in a controller to better organize logic. For example, one method might handle POST requests, while another handles GET requests.

## Linking Functions

For simple behavior, functions with the same signature as `handle` can be linked to controllers:

```dart
  router
    .route("/path")
    .linkFunction((req) async => req);
    .linkFunction((req) async => new Response.ok(null));
```

Linking a function has all of the same behavior: it can return a request or response, automatically handles exceptions, and can have controllers (and functions) linked to it. 

## Exception Handling

`Controller`s wrap `handle` in a try-catch block. If an exception is thrown during the processing of a request, it is caught and the controller will send a response on your behalf. The request is then removed from the channel and no more controllers will receive it.

By default, an uncaught exception will send a 500 Server Error response to the client. The error will be [logged](configure.md). For more control over the error response, an `HTTPResponseException`s can be thrown.

```dart
class SomeController extends Controller {
  Future<RequestOrResponse> handle(Request request) async {
    if (somethingBadHappened) {
      throw new HTTPResponseException(400, "Something bad happened.");
    }

    return new Response.ok(null);
  }
}
```

The message of an `HTTPResponseException` is encoded as JSON in the response body:

```json
{
  "error": "Something bad happened."
}
```

There are built-in subclasses of `HTTPResponseException` for features like the ORM, and you can create your own. `HTTPResponseException`s are not logged, because they are considered normal control flow for an application.

## Modifying a Response with Middleware

A middleware controller can modify the response created by an endpoint controller:

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

While this controller does not create a response for the request, another controller will. That response will have an 'x-api-version' header added to it before it is sent. More than one controller can add a response modifier, and each modifier is run in the order it are added to a request. The modifiers are run before any response body data is encoded.

## CORS Headers and Preflight Requests

`Controller`s have built-in behavior for handling CORS requests. They will automatically respond to `OPTIONS` preflight requests and attach CORS headers to any other response. See [the chapter on CORS](configure.md) for more details.
