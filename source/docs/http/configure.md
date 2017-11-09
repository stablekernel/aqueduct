# Configuring an Aqueduct Application

This guide covers configuring an Aqueduct application.

## Configuration Files

Aqueduct applications use YAML configuration files to provide environment-specific values like database connection information. Use separate configuration files for testing and different deployment environments.

The path of a configuration file is available to an `ApplicationChannel` through its `options` property.

```dart
class TodoAppChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    var config = new TodoConfiguration(options.configurationFilePath);
    ...
  }
}
```

The default value is `config.yaml`.

The best practice for reading a configuration file is to subclass `ConfigurationItem`. A `ConfigurationItem` declares a property for each key in a configuration file. For example, see the following `ConfigurationItem` subclass:

```dart
class TodoConfiguration extends ConfigurationItem {
  TodoConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
  String apiBaseURL;

  @optionalConfiguration
  int identifier;
}
```

This would read a YAML file like this:

```
database:
  username: fred
  password: fredspassword
  host: db.myapp.com
  port: 5432
  databaseName: fredsdb
apiBaseURL: /api
identifier: 2
```

If required properties are omitted from the YAML file being read, application startup will fail and throw an informative error.

You may use `ConfigurationItem`s to read values from environment variables. In `config.yaml`, use a `$`-prefixed environment variable name instead of a value:

```
database: $DATABASE_CONNECTION_URL
apiBaseURL: /api
```

If the environment variable `DATABASE_CONNECTION_URL`'s value were `"postgres://user:password@localhost:5432/test"`, the value of `TodoConfigurationItem.database` will be that string at runtime. (Note that `DatabaseConnectionConfiguration` may either a YAML object for each connection attribute, or a database connection string.)

The [safe_config package](https://pub.dartlang.org/packages/safe_config) has instructions for more additional usages.

### Configuration Conventions and Deployment Options

Aqueduct uses two configuration files for a project: `config.yaml` and `config.src.yaml`. The latter is the *configuration source file*. The configuration source file declares key-value pairs that will be used when running the application tests. Deployed instances use `config.yaml`.

This pattern is used for two reasons:

- It is the template for the `config.yaml` that will be read on deployed applications, providing documentation for your application's configuration.
- It has the configuration values used during testing to inject mock dependencies.

For example, a production API instance might have the following `config.yaml` file with connection info for a production database:

```
database: postgres://app_user:$%4jlkn#an*@mOZkea2@somedns.name.com:5432/production_db
```

Whereas `config.src.yaml` would have connection info for a local, test database:

```
database: postgres://test:test@localhost:5432/temporary_db
```

The source configuration file should be checked into version control. Whether or not `config.yaml` is checked in depends on how you are deploying your code. If you are using environment variables to control application configuration, you should check `config.yaml` into source control and provide `$`-prefixed environment variable values. If you are using managing configuration files on each deployed instance, do not check `config.yaml` into source control because it'll be a different file for each instance.

It can sometimes makes sense to have a `local.yaml` with values for running the application locally, e.g. when doing client testing. Use `--config-path` with `aqueduct serve` to use a non-default name.

## Preventing Resource Leaks

When an Aqueduct application starts, the application and its `ApplicationChannel`s will likely create services that they use to respond to requests. In order for application tests to complete successfully, these services must be "closed" when the application stops. For built-in services, like `PostgreSQLPersistentStore`, this happens automatically when `Application.stop()` is invoked.

A `ApplicationServiceRegistry` automatically stops registered services. Registration looks like this:

```dart
var connection = new ConnectionOfSomeKind();
await connection.open();
ApplicationServiceRegistry.defaultInstance
  .register<ConnectionOfSomeKind>(connection, (c) => c.close());
```

This method takes the service to be closed and a closure that closes it. The service is passed as an argument to the closure. If the closure returns a `Future`, `ApplicationServiceRegistry.close` will not complete until the `Future` completes. `ApplicationServiceRegistry.defaultInstance` is closed in `Application.stop()`, any registries created by the programmer must be closed manually.

The return type of `ApplicationServiceRegistry.register` is the object being registered. This makes registration syntax a bit more palatable:

```dart
var connection = ApplicationServiceRegistry.defaultInstance
  .register<ConnectionOfSomeKind>(
    new ConnectionOfSomeKind(), (c) => c.close());

await connection.open();  
```

## Configuring CORS Headers

All controllers have built-in behavior for handling CORS requests from a browser. When a preflight request is received from a browser (an OPTIONS request with Access-Control-Request-Method header and Origin headers), the response is created by evaluating the policy of the `Controller` that will respond to the real request.

In practice, this means that the policy of the last controller in a channel is used. For example, the policy of `FooController` is generates the preflight response:

```dart
router
  .route("/foo")
  .pipe(new Authorizer(...))
  .generate(() => new FooController());
```

Every `Controller` has a `policy` property (a `CORSPolicy` instance). The `policy` has properties for configuring CORS options for that particular endpoint. By having a `policy`, every `Controller` automatically implements logic to respond to preflight requests without any additional code.

Policies can be set at the controller level or at the application level. The static property `CORSPolicy.defaultPolicy` can be modified at initialization time to set the CORS options for every controller.

```dart
class MyApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    CORSPolicy.defaultPolicy.allowedOrigins = ["http://mywebsite.com/"];
  }
}
```

The default policy is very permissive: POST, PUT, DELETE and GET are allowed methods. All origins are valid (\*).

Each individual controller can override or replace the default policy by modifying its own `policy` in its constructor.

```dart
class MyRESTController extends RESTController {
  MyRESTController() {
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

When an application is started with these options, the `certificateFilePath` and `keyFilePath` are set on the `ApplicationOptions` your application is being run with. (If you are not using `aqueduct serve`, you can set these values directly when instantiating `ApplicationOptions`.)

For more granular control over setting up an HTTPS server, you may override `securityContext` in `ApplicationChannel`. By default, this property will create a `SecurityContext` from the `certificateFilePath` and `keyFilePath` in the channels's `options`. A `SecurityContext` allows for password-encrypted credential files, configuring client certificates and other less used HTTPS schemes.

```dart
class MyApplicationChannel extends ApplicationChannel {
  @override
  SecurityContext get securityContext {
    return new SecurityContext()
      ..usePrivateKey("server.key", password: "1234")
      ..useCertificateChain("server.crt", password: "1234");
  }
}
```
