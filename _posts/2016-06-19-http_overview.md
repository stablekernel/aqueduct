---
layout: page
title: "Overview"
category: http
date: 2016-06-19 21:22:35
order: 1
---

Aqueduct responds to HTTP requests. The primary components of handling HTTP requests are as follows:

- Routing HTTP Requests by their path
- Managing a stream of `RequestController`s that respond to requests or forward them on to subsequent controllers
- Subclassing `RequestSink` to provide initialization and an entry point for HTTP requests into an application
- Creating `Application` instances and spread them across isolates (threads)
- Using `HTTPController`s to respond to requests
- Using more focused RequestControllers like `ManagedObjectController` and `QueryController`
- Decoding HTTP request bodies and encoding objects into HTTP response bodies
- Handling CORS requests

### Guides

[Application and RequestSink](app_request_sink.html)
