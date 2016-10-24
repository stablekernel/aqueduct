---
layout: page
title: "The Application and RequestSink"
category: http
date: 2016-06-19 21:22:35
order: 3
---

The entry point into the application-specific code of an Aqueduct application is a `RequestSink`. A `RequestSink` must be subclassed, as it is responsible for setting up routes the application will respond to and instantiate resources to be used by those routes, like database connections. Instances of `Application<T>` create `RequestSink` instances and listen for HTTP requests. When an application receives an HTTP request, it wraps it in an Aqueduct `Request` instance and delivers it to one of the `RequestSink`s it manages. The request sink passes it on to the routes it has set up to process and respond to the request.

## Subclassing `RequestSink`

Every Aqueduct application must have a subclass of `RequestSink`. A `RequestSink` sets up streams of `RequestController`s that will respond to requests.

This subclass must override `RequestSink.setupRouter` to set up how requests are handled.

 Routes are registered with an instance of `Router` (see [routing.html])
