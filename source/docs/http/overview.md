## Tasks

Aqueduct applications respond to HTTP requests. The main concepts and tasks are:

- Setting up routes and initializing an application by subclassing `ApplicationChannel`
- Subclassing `RESTController` to fulfill requests
- Starting and stopping Aqueduct Applications with `aqueduct serve`
- Binding a REST interface to a database table with `ManagedObjectController<T>`
- Encoding and Decoding HTTP request and response bodies according to `HTTPCodecRepository`
- Adding middleware to a channel to route and validate requests

## Guides

- [Architecture and Organization of Aqueduct Applications](structure.md)
- [Request and Response Objects](request_and_response.md)
- [Handling Requests](controller.md)
- [The ApplicationChannel](channel.md)
- [Routing](routing.md)
- [RESTControllers](rest_controller.md)
- [Configuration Files, CORS and SSL](configure.md)
- [Serving Files and Caching](serving_files.md)
- [Websockets](websockets.md)
- [Multi-threading](threading.md)
