## Tasks

Aqueduct applications respond to HTTP requests. The main concepts and tasks are:

- Using a `Router` to determine which code is run for an HTTP request
- *Binding* the values from an HTTP request to the parameters of a method with `HTTPController`
- Setting up routes and initializing an application by subclassing `RequestSink`
- Starting and stopping Aqueduct Applications with `aqueduct serve`
- Binding an REST interface to a database table with `ManagedObjectController<T>`
- Encoding and Decoding HTTP request and response bodies according to `HTTPCodecRepository`
- Building pipelines with middleware

## Guides

- [Architecture and Organization of Aqueduct Applications](structure.md)
- [Request and Response Objects](request_and_response.md)
- [Handling Requests](request_controller.md)
- [The RequestSink](request_sink.md)
- [Routing](routing.md)
- [HTTPControllers](http_controller.md)
- [Configuration Files, CORS and SSL](configure.md)
- [Serving Files and Caching](serving_files.md)
- [Websockets](websockets.md)
- [Multi-threading](threading.md)
