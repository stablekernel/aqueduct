---
layout: page
title: "Request and Response Objects"
category: http
date: 2016-06-19 21:22:35
order: 3
---

In Aqueduct, HTTP requests and responses are instances of `Request` and `Response`, respectively. For every HTTP request an application receives, an instance of `Request` is created. A `Response` must be created for each `Request`. Requests pass through a series of [RequestControllers](request_controller.html) to be validated, modified and finally responded to.

## The Request Object

An instance of `Request` has the information in an HTTP request. They are automatically created when the application receives an HTTP request and are passed to your application's `RequestSink`. A `Request` also has additional storage to collect information as it passes through `RequestController`s. A `Request` is a wrapper around the Dart standard library `HttpRequest` and its values - such as headers - can be accessed through its `innerRequest`. (Just don't write to its `Response` - Aqueduct does that.)

A `Request` has an `HTTPBody` property, `body`. This property contains the HTTP request body. An `HTTPBody` decodes the contents of a request body from a transmission format like JSON or XML into Dart objects, like `Map`, `String` and `List`. The mechanism to decode the body is determined by decoders available in `HTTPBody`. By default, decoders exist for text, JSON and form data. New decoders can be added with `HTTPBody.addDecoder()`.

A `Request` may go through many `RequestController`s before it is finally responded to. These `RequestController`s may validate or add more information to the request as it passes through. For example, an `Authorizer` - a subclass of `RequestController` - will validate the Authorization header of a request. Once validated, it will add authorization info to the request and pass it to the next `RequestController`. The next controller then has access to the request's authorization info.

These additional values are added to a `Request`'s `attachments` property. A `Request` also has two built-in attachments, `authorization` and `path`. `authorization` contains authorization information created by an `Authorizer` and `path` has request path information created by a `Router`.

`Request`s are responded to by invoking `respond` on them. Instances of `RequestController` invoke this method as part of their  on your behalf (see [RequestControllers](request_controller.html)). Once a request has been responded to, it *cannot* be responded to again. Because `RequestController`s invoke `respond` on your behalf, it is important that you never invoke `respond` explicitly - otherwise a request controller will try responding to an already responded to request.

## Response Objects and HTTP Body Encoding

An instance of `Response` represents all of the information needed to send a response to a client: a status code, HTTP headers and an HTTP body. There are a number of convenience constructors for `Response` for commonly used status codes. For example, `Response.ok` creates a 200 OK status code response.

```dart
var response = new Response.ok({"key": "value"});
```

`Response`s are returned from a `RequestController`'s `processRequest` and Aqueduct manages sending that response back to the client.  Therefore, subclasses of `RequestController` must override `processRequest` to create a `Response`. Some subclasses of `RequestController`, like `HTTPController`, override this method and allow `Response`s to be created in more meaningful ways.

A `Response`'s body gets encoded according to its Content-Type. The `Response` class has a set of encoders that will take Dart objects and encode them to data that will be the HTTP response body. By default, JSON and text are supported encoders, but new ones can be added with `Response.addEncoder`.

The type of the `body` property of a `Response` depends the content type of the response. More often than not, the content type is JSON and the `body` can be anything that can be passed to `JSON.encode`. This means `Map`s and `List`s that contain only `String`, `int`, `double`, `bool` or other `Map`s and `List`s that contain only these types, too.

Values that implement `HTTPSerializable` (or are a `List<HTTPSerializable>`) can also be used as the `body` of a `Response`. This interface allows any Dart object to be represented as a `Map`.

The content type of a `Response` is set through its `contentType` property.

```
var object = new ObjectThatImplementsHTTPSerializable();
var response = new Response.ok(object)
  ..contentType = ContentType.JSON;
```

If the body cannot be encoded, an exception is thrown and a 500 status code is returned to the HTTP client.
