---
layout: page
title: "Overview"
category: http
date: 2016-06-19 21:22:35
order: 1
---

Aqueduct responds to HTTP requests. The primary components of handling HTTP requests are as follows:

- Routing HTTP Requests by their path
- Managing a stream of `Request`s that `RequestController`s listen to, which respond to requests are pass them downstream
- Subclassing `RequestSink` to provide initialization and an entry point for HTTP requests into an application
- Creating `Application` instances and spread them across isolates (threads)
- Using `HTTPController`s to respond to requests
- Using more focused RequestControllers like `ManagedObjectController` and `QueryController`
- Decoding HTTP request bodies and encoding objects into HTTP response bodies
- Handling CORS requests

## Guides

- [Request and Response Objects](request_and_response.html)
- [Handling Requests](request_controller.html)
- [Application and RequestSink](request_sink.html)
- [Routing](routing.html)
