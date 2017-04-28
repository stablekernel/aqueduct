## Tasks

Aqueduct responds to HTTP requests. The main concepts and tasks are:

- Using a `Router` to dispatch `Request`s to a `RequestController`
- Using `RequestController`s to process, modify and respond to `Request`s
- Subclassing `RequestSink` to handle application initialization
- Running Aqueduct Applications with `aqueduct serve`
- Subclassing `HTTPController` to group routes and create responses
- Using helpful controllers like `QueryController<T>` and `ManagedObjectController<T>`.
- Decoding HTTP request bodies with `HTTPBody` and encoding objects into HTTP response bodies with `Response`
- Handling CORS requests with `CORSPolicy`

## Guides

- [Structure of Aqueduct Application](structure.md)
- [Request and Response Objects](request_and_response.md)
- [Handling Requests](request_controller.md)
- [The RequestSink](request_sink.md)
- [Routing](routing.md)
- [HTTPControllers](http_controller.md)
- [Configuration Files, CORS and SSL](configure.md)
