# Configuring an Aqueduct Application

This guide covers configuring an Aqueduct application.

## Configuration Files

## Preventing Resource Leaks

When an Aqueduct application starts, the application and its `RequestSink`s will likely open connections and streams that they use to respond to requests. In order for application tests to complete successfully, these connections and streams must be closed when the application stops. For built-in connections and streams, like `PostgreSQLPersistentStore`, this happens automatically when `Application.stop()` is invoked.

Objects that need to be closed can be registered with `ResourceRegistry` to automatically be closed when the application is stopped. Registration looks like this:

```dart
var connection = new ConnectionOfSomeKind();
await connection.open();
ResourceRegistry.add<ConnectionOfSomeKind>(connection, (c) => c.close());
```

The object to be closed is the first argument and a closure to close it is the second argument. The argument passed to this closure is the object being closed. The closure must return a `Future` that completes with the resource has finished closing. All registered resources are closed when an application is stopped.

The registry is per-isolate. This means that each isolate spawned for a `RequestSink` and the main isolate that runs `RequestSink.initializeApplication()` each have their own registry. This detail should not matter - you must only register each closable resource.

The return type of `ResourceRegistry.add` is the object being registered. This makes registration syntax a bit more palatable:

```dart
var connection = ResourceRegistry.add<ConnectionOfSomeKind>(
  new ConnectionOfSomeKind(), (c) => c.close());
await connection.open();  
```

## Configuring CORS

All request controllers have built-in behavior for handling CORS requests from a browser. When a preflight request is received from a browser (an OPTIONS request with Access-Control-Request-Method header and Origin headers), any request controller receiving this request will immediately pass it on to its `nextController`. The final controller listening to the stream will use its policy to validate and return a response to the HTTP client. This allows the final responding controller - typically a subclass of `HTTPController` - to determine CORS policy.

Every `RequestController` has a `policy` property, of type `CORSPolicy`. The `policy` has properties for configuring CORS options for that particular endpoint. By having a `policy`, every `RequestController` automatically implements logic to respond to preflight requests without any additional code.

Policies can be set at the controller level or at the application level. The static property `CORSPolicy.defaultPolicy` can be modified at initialization time to set the CORS options for every controller.

```dart
class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config) {
    CORSPolicy.defaultPolicy.allowedOrigins = ["http://mywebsite.com/"];
  }
}
```

The default policy is very permissive: POST, PUT, DELETE and GET are allowed methods. All origins are valid (\*).

Each individual controller can override or replace the default policy by modifying its own `policy` in its constructor.

```dart
class MyHTTPController extends HTTPController {
  MyHTTPController() {
    policy.allowedMethods = ["POST"];
  }
}
```

## Configuring HTTPS

By default, an Aqueduct application does not use HTTPS. In many cases, an Aqueduct application sits behind an SSL-enabled load balancer or some other proxy. The traffic from the load balancer is sent to the Aqueduct application unencrypted over HTTP.

However, Aqueduct may be configured to manage HTTPS connections itself. By passing the value private key and SSL certificate paths as options to `--ssl-key-path` *and* `--ssl-certificate-path` in `aqueduct serve`, an Aqueduct application will configure itself to only allow HTTPS connections.

```sh
aqueduct serve --ssl-key-path server.key.pem --ssl-certificate-path server.cert.pem
```

Both the key and certificate file must be unencrypted PEM files, and both must be provided to this command. These files are typically issued by a "Certificate Authority", such as [letsencrypt.org](letsencrypt.org).

When an application is started with these options, the `certificateFilePath` and `keyFilePath` are set on the `ApplicationConfiguration` your application is being run with. (If you are not using `aqueduct serve`, you can set these values directly when instantiating `ApplicationConfiguration`.)

For more granular control over setting up an HTTPS server, you may override `securityContext` in `RequestSink`. By default, this property will create a `SecurityContext` from the `certificateFilePath` and `keyFilePath` in the sink's `configuration`. A `SecurityContext` allows for password-encrypted credential files, configuring client certificates and other less used HTTPS schemes.

```dart
class MyRequestSink extends RequestSink {
  @override
  SecurityContext get securityContext {
    return new SecurityContext()
      ..usePrivateKey("server.key", password: "1234")
      ..useCertificateChain("server.crt", password: "1234");
  }
}
```
