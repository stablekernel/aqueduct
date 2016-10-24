---
layout: page
title: "Request Controllers"
category: http
date: 2016-06-19 21:22:35
order: 2
---

Instances of `RequestController` are responsible for processing HTTP requests. Request controllers are chained together to form streams that process particular requests. A request controller may respond to a request or it may forward a request on to the next request controller in a stream. A `RequestController` wraps request handling in a try-catch block to ensure that even if there is an error, the request is responded to.

## `RequestController` Streams

A request controller receives requests through its `receive` method. A controller can either by respond to the request or defer the request to the next controller in the stream. A controller makes this decision by implementing `RequestController.processRequest`. This method takes a `Request` as input, and must return a `Future<Response>` or `Future<Request>` as output.

The return `Request` or `Response` is always wrapped in a `Future` so that the processing of the request can be done asynchronously - such as the case for endpoints that make database requests or other I/O operations.

If a controller returns a `Future<Response>` from `processRequest`, that object is used to send the HTTP response to the client and the request is discarded. If the controller returns a `Future<Request>`, the `RequestController` will deliver the request to the next controller in the stream. This delivery is through the `receive` method, and thus the above process starts again.

Subclasses of `RequestController` override `processRequest` to carry out their unique handling of a request. The implementation of this method should not attempt to manage delivery on the stream of `RequestController`s. For example, passing a request on to the next controller from within `processRequest` would cause a serious error.

`RequestController`s store the next controller in a stream in their `nextController` property. Therefore, a stream of request controllers is linear. Controllers that split a stream - like `Router` - override `receive` and manage their own set of substreams. Overriding `receive` is more complex than overriding `processRequest` and is rarely necessary.

The `nextController` property is not set directly. Instead, the methods `pipe`, `generate` and `listen` are used to add controllers to a stream. Each one of these methods registers a `nextController` and then returns that controller. This allows for chaining together stream methods to create a stream in a single line. For example, the following sets up a stream of request controllers of types A, B and C in that order:

```dart
  var controller = new A();
  controller
    .pipe(new B(...))
    .pipe(new C(...))
    ...
```

Whether to use `pipe`, `generate` or `listen` depends on the type of `RequestController` being added to the stream. The most basic stream method is `listen`. This stream method takes a closure that must be the same signature as `processRequest`, effectively creating a new `RequestController` that replaces `processRequest` with the closure.

```dart
controller
  .listen((req) async {
    if (shouldRespondToReq(req)) {
      return new Response.ok(...);
    }

    return req;
  });
```

Both `pipe` and `generate` will add an instance of `RequestController` (or subclass) to the stream. `generate` will create a new instance of the `RequestController` for each request, where `pipe` will reuse the same instance. Choosing between the two is depends on whether or not the controller has any properties that will change when it receives a request.

For example, an `HTTPController` has a property that holds the request it is processing and therefore instances must be generated for each request. An `Authorizer`, on the other hand, does not keep any state, so it can be safely piped to. The `pipe` method just takes an instance of some `RequestController` as an argument, while `generate` takes a closure that returns a new instance of the desired `RequestController`:

```dart
controller
  .pipe(new Authorizer(...))
  .generate(() => new HTTPController());
```

The reasoning for this behavior is simple: an Aqueduct application can process more than one request at a time. If an `HTTPController` is processing a request - setting its `request` property - and then `await`s on a database query, a new request can be processed. Processing this request would set the `HTTPController`'s request property to the new request. When the database query completes and execution resumes in the `HTTPController`, the request will have changed out from underneath it. This would be bad.

Subclasses of `RequestController` can have `@cannotBeReused` metadata that indicates they must be generated. When attempting to set up a stream that `pipe`s to a controller with this metadata, an exception will be thrown.

There are a number of built-in subclasses of `RequestController` that are covered in greater depth in the documentation. Some of those are `QueryController`, `ManagedObjectController`, `HTTPController`, `Authorizer`, `Router` and `RequestSink`.

## Exception Handling

If an exception is thrown while a processing a request, it will be caught by the `RequestController` in charge. The controller will respond to the HTTP request with an appropriate status code and no subsequent controllers will be sent the request.

There are two types of exceptions that a `RequestController` will interpret to return a meaningful status code: `HTTPResponseException` and `QueryException`. Any other exceptions will result in a 500 status code error.

`QueryException`s are generated by using the Aqueduct ORM. A request controller interprets these types of exceptions to return a suitable status code. The following reasons for the exception generate the following status codes:

|Reason|Status Code|
|---|---|
|A programmer error (bad query syntax)|500|
|Unique constraint violated|409|
|Invalid input|400|
|Database can't be reached|503|

An `HTTPResponseException` can be thrown at anytime to escape early from processing and return a response. Exceptions of these type allow you to specify the status code and a message. The message is encoded in a JSON object for the key "error". Some classes in Aqueduct will throw an exception of this kind if some precondition isn't met. For example, `AuthorizationBearerParser` throws this exception if there is no authorization header to parse.

You may add your own try-catch blocks to request processing code to either catch and reinterpret the behavior of `HTTPResponseException` and `QueryException`, or for any other reason.

Exceptions are always logged along with some details of the request that spawned the exception.

## Routing

The root of a request controller stream in an Aqueduct application is typically a `Router`. A router is a `RequestController`, but it behaves slightly differently - it does not pass requests along a linear stream, but instead, splits the stream based on the path of the HTTP request.

This topic is covered in [routing.html].

## CORS Support

All request controllers have built-in behavior for handling CORS requests from a browser. Aqueduct will treat an HTTP request as a CORS request if it has the `Origin` header. When a request controller receives a request with this header, it will go to the last controller in the stream and ask for its `policy` property. It validates the origin against the policy and applies the appropriate headers in the response.

When a preflight request is received from a browser (an OPTIONS request with Access-Control-Request-Method header and Origin headers), any request controller receiving this request will immediately pass it on to its `nextController`. The final controller in the stream will use its policy to validate and return a response to the HTTP client.

Using the last controller in a stream allows endpoints to decide on the validity of a CORS request. Thus, even if a request doesn't make its way through the stream - perhaps because it failed to be authorized - the response will have the appropriate headers to indicate to the browser the acceptable operations for that endpoint.

Every `RequestController` has a default policy. This policy can be changed on a per-controller basis by modifying it in the controller's constructor.

The default policy may also be changed at the global level by modifying `CORSPolicy.defaultPolicy`. The default policy is permissive: POST, PUT, DELETE and GET are allowed methods. All origins are valid (\*). Authorization, X-Requested-With and X-Forwarded-For are allowed request headers, along with the list of simple headers: Cache-Control, Content-Language, Content-Type, Expires, Last-Modified, Pragma, Accept, Accept-Language and Origin.
