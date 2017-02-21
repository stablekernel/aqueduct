---
layout: page
title: "Request and Response Objects"
category: http
date: 2016-06-19 21:22:35
order: 3
---

In Aqueduct, HTTP requests and responses are instances of `Request` and `Response`, respectively. For every HTTP request an application receives, an instance of `Request` is created. A `Response` must be created for each `Request`. Requests pass through a series of [RequestControllers](request_controller.html) to be validating, modified and finally responded to.

## The Request Object

An instance of `Request` has the information in an HTTP request. It also has additional storage to collect information as it passes through `RequestController`s. A `Request` is a wrapper around the Dart standard library `HttpRequest` and its values - such as headers - can be accessed through its `innerRequest`. (Just don't write to its `Response` - Aqueduct does that.)

A `Request` has an `HTTPBody` property, `body`. This instance contains the request body. An `HTTPBody` decodes the contents of a request body from a transmission format like JSON or XML into Dart objects, like `Map`, `String` and `List`. The mechanism to decode the body is determined by decoders available in `HTTPBody`. By default, decoders exist for text, JSON and form data. New decoders can be added with `HTTPBody.addDecoder()`.

A `Request` goes through many `RequestController`s before it is finally responded to. These `RequestController`s may validate or add more information to the request as it passes through. For example, an `Authorizer` - a subclass of `RequestController` - will validate the Authorization header of a request. Once validated, it will add authorization info to the request and pass it to the next `RequestController`. The next controller then has access to the request's authorization info.

These additional values are added to a `Request`'s `attachments` property. A `Request` also has two built-in attachments, `authorization` and `path`. `authorization` contains authorization information created by an `Authorizer` and `path` has request path information created by a `Router`.

Instances of `RequestController`
`Request`s are responded to by invoking `respond` on them. Instances of `RequestController` invoke this method as part of their  on your behalf (see [RequestControllers](request_controller.html)). Once a request has been responded to, it *cannot* be responded to again. Because `RequestController`s invoke `respond` on your behalf, it is important that you never invoke `respond` explicitly - otherwise a request controller will try responding to an already responded to request.

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
