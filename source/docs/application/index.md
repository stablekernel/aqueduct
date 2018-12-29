## Tasks

An Aqueduct application starts an HTTP server and invokes your code for each request. The code that is invoked might depend on the request's path, method, and other attributes. For example, the request `GET /heroes` will invoke different code than `POST /authors`. You configure which code is invoked in an `ApplicationChannel` subclass; every application declares exactly one `ApplicationChannel` subclass.

This subclass also sets up services, reads configuration data from files and environment variables and performs any other initialization for your application. For example, an application channel often reads database connection information from environment variables and then sets up a connection to that database.

Aqueduct applications create multiple threads, and each thread takes turn handling incoming requests. Your application channel subclass is created for each thread, creating replica instances of your application.

## Guides

- [Starting and Stopping Applications](channel.md)
- [Configuring an Application and its Environment](configure.md)
- [Application and Project Structure](structure.md)
- [Performance: Multi-threading](threading.md)
