## Tasks

Aqueduct applications respond to HTTP requests. The main concepts and tasks are:

- Using a `Router` to dispatch `Request`s to a `RequestController`
- Subclassing `HTTPController` to bind requests and their properties to *responder methods*
- Subclassing `RequestSink` to initialize an application
- Running Aqueduct Applications with `aqueduct serve`
- Using specialized database controllers like `QueryController<T>` and `ManagedObjectController<T>`.
- Decoding HTTP request bodies with `HTTPRequestBody` and encoding objects into HTTP response bodies with `Response`
- Using `RequestController`s to implement middleware and other types of responder logic.

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
