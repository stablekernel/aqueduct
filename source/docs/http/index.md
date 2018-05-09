## Tasks

An Aqueduct application serves HTTP clients by sending responses for requests.

You create and link `Controller` objects to handle requests. There are many subclasses of `Controller` that handle common tasks, and you often create your own subclasses of `Controller` to implement middleware and endpoint logic. Most of your endpoint logic is implemented in subclasses of `ResourceController`, a controller type geared for REST API endpoints.

You create a subclass of `ApplicationChannel` to configure controllers used by your application. This subclass also initializes any services your application will use to fulfill requests, like database connections or third party API connections. Most often, you use a `Router` controller at the entry point of your application channel to modularize your application logic.

Your application may have many configurable options. This configuration is handled in your application channel. Configuration file management is provided by application-specific `ConfigurationItem` subclasses that add type and name safety to your configuration files.

Your application is run by using the `aqueduct serve` command or the `bin/main.dart` script. In either case, your application starts by creating multiple, memory-isolated threads that replicate your `ApplicationChannel`.

## Guides

- [Architecture and Organization of Aqueduct Applications](structure.md)
- [Request and Response Objects](request_and_response.md)
- [Handling Requests](controller.md)
- [The ApplicationChannel](channel.md)
- [Routing](routing.md)
- [ResourceControllers](resource_controller.md)
- [Configuration Files, CORS and SSL](configure.md)
- [Serving Files and Caching](serving_files.md)
- [Websockets](websockets.md)
- [Multi-threading](threading.md)
