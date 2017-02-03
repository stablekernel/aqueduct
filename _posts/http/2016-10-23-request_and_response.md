---
layout: page
title: "Request and Response Objects"
category: http
date: 2016-06-19 21:22:35
order: 2
---

In Aqueduct, HTTP requests and responses are represented as instances of `Request` and `Response`, respectively. For every HTTP request an application receives, an instance of `Request` is created. These requests are passed through a series of [RequestControllers](request_controller.html), whose job is to create a `Response` for the request.

## The Request Object

An instance of `Request` contains the information from an HTTP request. It also has helpful methods for accessing that information in more productive ways and storage to gather extra, application-specific information as it passes through processing steps.

The actual request information is stored in `Request.innerRequest`, an instance of the Dart standard library `HttpRequest`. For accessing simple values like headers or the query string, use this property. It is important that the `response` of `innerRequest` is not written to - Aqueduct will handle responding to requests.

A `Request` knows how to decode its HTTP request body into Dart objects. Requests do not immediately decode their body when they are received, they wait until something invokes their `decodeBody` method. (Note: `HTTPController` will invoke this automatically on a request prior to calling a responder method.) This prevents wasting precious CPU cycles on decoding if the request isn't going to be processed because it gets rejected in an early validation step. Once a `Request` has been decoded, the Dart object that represents the body will be available in its `requestBodyObject` property. For example, if request body is a JSON object, `requestBodyObject` is an instance of `Map<String, dynamic>` after decoding.

```dart
Request request = ...;

// The body object is null initially
request.requestBodyObject == null; // true

// After decode, the body object is non-null (if there was an HTTP body), and
// requestBodyObject is set.
var body = await request.decodeBody();
request.requestBodyObject == body; // true
```

The actual decoding behavior is performed by the class `HTTPBodyDecoder`. This class has a `Map` of decoders, where the key is a `ContentType` and the value is a function that transforms the body into Dart objects. By default, `HTTPBodyDecoder` knows how to decode `application/json`, `application/x-www-form-urlencoded` and `text/*` bodies. You may add additional decoders with `HTTPBodyDecoder.addDecoder` to support more content types.

A `Request` also has *attachments* that get added to it as it travels through a series of `RequestController`s. This allows requests to accumulate information as they pass validation phases. Subsequent `RequestController`s can use this information to make decisions about handling the request, without having to duplicate the work of deriving that information.

For example, a request that must be authorized to reach an endpoint must pass through an `Authorizer`. An `Authorizer` will evaluate the Authorization header of the request and determine what user the credentials refer to, attaching this user information to `Request.authorization` property. Subsequent `RequestController`s can access this information to scope the resources the client has access to.

Custom `RequestController` subclasses can add their own values to `Request.attachments`, which is a `Map<String, dynamic>`.

`Request`s are responded to by invoking `Request.respond`. However, you do not invoke this method directly. Instead, instances of `RequestController` invoke it on your behalf (see [RequestControllers](request_controller.html)). Once a request has been responded to, it *cannot* be responded to again. Because `RequestController`s invoke `respond` on your behalf, it is important that you never invoke `respond` explicitly - otherwise a request controller will try responding to an already responded to request.

## Response Objects and HTTP Body Encoding

An instance of `Response` represents all of the information needed to send a response to a client for a `Request`: a status code, HTTP headers and an HTTP body. There are a number of convenience constructors for `Response` for commonly used status codes. For example, `Response.ok` creates a 200 OK status code response.

A `Response` will serialize its `body` property if it implements `HTTPSerializable` or is a `List<HTTPSerializable>`. Serializing will transform these objects into encodable, primitive values - `String`, `int`, `double`, `bool`, or `Map`s and `List`s containing those types. The `body` may also be made up of those types to begin with. This serialization process occurs as soon as the `Response` object is created.

```dart
var response = new Response.ok({
  "a" : 1
});

HTTPSerializable complexObject = ...;
var response = new Response.ok(complexObject);

response.body is Map == true;
```

Prior to sending a response, the body of a `Response` is encoded according to its Content-Type header. If no Content-Type header has been set for a `Response`, the default is "application/json". There are encoders for "application/json" and "plain/text" available in Aqueduct. New encoders can be added with `Response.addEncoder`. The map of encoders behaves the same way as `HTTPBodyDecoder` - the key is a `ContentType` and the value is a function that takes Dart objects and encodes them into a value that can be represented in an HTTP response body.

```dart
// The following three responses will all encode their body as JSON.
var response = new Response.ok({
    "a" : a
});

var response = new Response.ok({
    "a" : a
}, headers: {
  HttpHeaders.CONTENT_TYPE : ContentType.JSON
});

var response = new Response.ok({
    "a" : a
}, headers: {
  "Content-Type": "application/json"
});
```

The value of the Content-Type header may be either a `ContentType` or a `String` - either will be correctly interpreted when sending a response. If the body cannot be encoded or serialized, an exception is thrown and a 500 status code is returned to the HTTP client.

`Response` instances are created and returned from `RequestController.processRequest` so that the internal mechanisms of `RequestController` can write a response to the client. For early-returning from processing a request, see `HTTPResponseException`.
