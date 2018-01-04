# Testing in Aqueduct

From the ground up, Aqueduct is built to be tested. In practice, this means two things:

- A deployed Aqueduct application has zero code differences from an Aqueduct application under test.
- There are helpful utilities for writing tests in Aqueduct.

## How Tests are Written

A project created with `aqueduct create` contains a test harness (in `test/harness/app.dart`) for starting and stopping an application. A very simple harness looks like this:

```dart
import 'package:myapp/myapp.dart';
import 'package:aqueduct/test.dart';

export 'package:myapp/myapp.dart';
export 'package:aqueduct/test.dart';
export 'package:test/test.dart';
export 'package:aqueduct/aqueduct.dart';

class TestApplication {
  Application<AppChannel> application;
  AppChannel get channel => application.channel;
  TestClient client;

  Future start() async {
    Controller.letUncaughtExceptionsEscape = true;
    application = new Application<AppChannel>();
    application.options.port = 0;
    application.options.configurationFilePath = "config.src.yaml";

    await application.test();

    client = new TestClient(application);
  }

  Future stop() async {
    await application?.stop();
  }  
}
```

Replace the type argument for `application` with your `ApplicationChannel` subclass. A test file need only import this harness and start and stop the application in its `setUpAll` and `tearDownAll` callbacks:

```dart
import 'harness/app.dart';

void main() {
  var app = new TestApplication();
  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });
}
```

Note that a test file must be in the `test/` directory of a project and its file name must end with `_test.dart`.

When executing tests, you use the test harness' `client` to issue requests and verify their response:

```dart
test("That we get a 200 from /endpoint", () async {
  var response = await app.client.request("/endpoint").get();

  expect(response, hasStatus(200));
});
```

## Using a TestClient

A `TestClient` creates requests (instances of `TestRequest`), which have execution methods (like `get` and `post`) that return responses (instances of `TestResponse`). The purpose of an Aqueduct test is to ensure that a request elicits the intended response. For example, you may want to make sure that a request with all the right parameters returns a response with the expected status code and JSON response body. Likewise, you may want to ensure that a request with some invalid parameters returns a response with the appropriate error information.

A `TestClient` provides constant information - like the base URL, default headers or default credentials - to the instances of `TestRequest` it creates. There are three methods for creating a request. The path is a required argument to each and need not include the base URL, port or any other information other than the path. The most basic method for creating a request is simply `request` (we'll discuss the other three shortly):

```dart
var request = app.client.request("/endpoint");
```

A `TestRequest` can be configured with additional headers, request body data and query parameters before being executed. There are conveniences for different types of data. For example, it is often the case to add a JSON request body. The following will automatically encode a JSON request body from Dart objects and set the Content-Type of the request to `application/json; charset=utf-8`:

```dart
var request = app.client.request("/endpoint")
  ..json = {
    "id": 1,
    "something": "else"
  };
```

Headers can be added directly with `headers` or `addHeader`, where some more commonly used headers have exposed properties:

```dart
request
  ..addHeader("x-application-id", "something")
  ..accept = [ContentType.JSON];
```

Once configured, an execution method returns a `Future<TestResponse>` for the request. There are execution methods for each of the primary HTTP methods:

```dart
var response = await request.post();
```

See a [later section](#verifying-responses) on how to verify elements of a response.

### Testing Authorized Endpoints

Most applications will have some form of authorization for its endpoints. For this purpose, both `TestClient` and `TestRequest` have behavior for managing authorization headers during testing. A `TestRequest`'s authorization header can be set by one of the two following methods:

```dart
// Base64 encodes username:password, sets 'Authorization: Basic base64String'
request.setBasicAuthorization("username", "password");

// Sets 'Authorization: Bearer Abcaklaerj893r3jnjkn'
request.bearerAuthorization = "Abcaklaerj893r3jnjkn";
```

You may also create requests with an authorization header through `TestClient`:

```dart
var request = app.client.clientAuthenticatedRequest(
  "/endpoint", clientID: "username", clientSecret: "password");

var request = app.client.authenticatedRequest(
  "/endpoint", accessToken: "Abcaklaerj893r3jnjkn");
```

The value of `clientAuthenticatedRequest` and `authenticatedRequest` is that defaults can be provided to the `TestClient` for the username, password or access token.

```dart
app.client.defaultAccessToken = "Abcaklaerj893r3jnjkn";

// Automatically includes header 'Authorization: Bearer Abcaklaerj893r3jnjkn'.
var request = app.client.authenticatedRequest("/endpoint");
```

See a [later section](#configuring-the-test-harness) for more details on setting up tests that use authorization.

## Verifying Responses

Once a `TestRequest` is executed and returns a `TestResponse`, the real work begins: verifying the response is what you expect. A `TestResponse` has properties for the things you would typically expect of an HTTP response: status code, headers and body. In addition to the raw string `body` property, the following body-inspecting properties exist:

- `decodedBody` is the object created by decoding the response body according to its content-type
- `asList` is `decodedBody`, but cast to a `List`
- `asMap` is `decodedBody`, but cast to a `Map`

The great part about each of these three methods is that if the body cannot be decoded according to its content-type, or cannot be cast into the expected type, an exception is thrown and your tests fail. In other words, these methods implicitly test the validity of the response body.

Using individual properties of a `TestResponse` in test expectations is a valid use case, but there are some more helpful utilities for verifying responses more clearly.

The most important matcher is `hasResponse`. This matcher verifies a status code, headers and response body in a single function call. For example:

```dart
test("Get 200 with key value pair", () async {
  var response = await app.client.request("/endpoint").get();

  expect(response, hasResponse(200, {
    "key": "value"
  }, headers: {
    "x-app": "abcd"
  }));
});
```

This will validate that not only does the response have a 200 status code, but its body - after decoding - is a `Map` that contains `key: value` and it has the header `x-app: abcd`.

Matchers from the official Dart test package can be mixed and matched into `hasResponse`:

```dart
test("Get 200 with key value pair", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, {
      "count": greaterThan(1)
  }));
});
```

This ensures that the response's body is a map, for which the key `count` has a value greater than 1. We can get even cuter - this test ensures that the body is a list of objects where every one is a map with the same property:

```dart
test("Get 200 with a lot of key value pairs", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, everyElement({
      "count": greaterThan(1)
  })));
});
```

Another valuable matcher is `partial`. Sometimes it doesn't make sense to validate every single key-value pair in a response. The `partial` matcher only checks that the body has the specified keys - extra keys don't create a mismatch.

```dart
test("Get 200 that at least have these keys", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, partial({
    "key1": isInteger,
    "key2": isString,
    "key3": isTimestamp
  })));
});
```

Even if the response has keys 4, 5 and 6, as long as the values for keys 1, 2 and 3 match, this test will pass.

When using `partial`, you can also ensure that a map doesn't have a key with the `isNotPresent` matcher.

```dart
test("Get 200 that at least have these keys", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, partial({
    "key3": isNotPresent
  })));
});
```

This ensures that `key3` is not in the map. This is different than verifying `key3: null`, which would be true if `key3`'s value was actually the null value. See the API reference for more matchers.

See the [API Reference](https://www.dartdocs.org/documentation/aqueduct/latest/aqueduct.test/aqueduct.test-library.html) for `aqueduct/test` for more behaviors.

### Verifying Other Data Not in the Response

Some requests will trigger changes that are not readily available in the response. For example, if a request uploads a file, the response doesn't necessarily tell you that uploading succeeded. For that reason, you may want to verify data stores and other services the application has after issuing a request.

Recall from the test harness at the top of this guide, the method `Application.test` is invoked. This method starts the application, but turns off Aqueduct's multi-isolate behavior and runs the application on the same isolate running your tests. When running on the main isolate, the application's channel and services are directly available to the test code. This allows you to verify any expected side-effects of a request. For example, by executing a query against a database:

```dart
test("Starting an upload creates a pending record in the database", () async {
  var req = app.client.request("/upload")
    ..contentType = ContentType.TEXT
    ..body = someFileContents;
  var response = await req.post();
  expect(response, hasStatus(202));

  var query = new Query<Upload>()
    ..where.pending = whereEqualTo(true);
  var pendingUpload = await query.fetchOne();

  expect(response.headers.value(HttpHeaders.LOCATION), pendingUpload.path);
});
```

Anything the `ApplicationChannel` can access, so too can the tests.

## Configuring the Test Harness

The test harness' primary responsibility is to start and stop the application. Recall from earlier in this guide, the test harness started an application like so:

```dart
Future start() async {
  Controller.letUncaughtExceptionsEscape = true;
  application = new Application<AppChannel>();
  application.options.port = 0;
  application.options.configurationFilePath = "config.src.yaml";

  await application.test();

  client = new TestClient(application);
}
```

There are some interesting things to note here. First, the setting of `Controller.letUncaughtExceptionsEscape`. This property defaults to false - if an unknown exception is thrown in request handling code, the `Controller` catches it and send a 500 Server Error response to the client. This is an important behavior for a deployed Aqueduct application - the client gets back a response and your application continues running.

However, when this flag is set to true, an uncaught exception will halt the application and fail the tests. This is the behavior you want during testing - it tells you something is wrong and gives you a stack trace to hunt down the problem.

By setting the port number to 0, the application listens on a random, unused port. This allows test suites to run in parallel - the `TestClient` takes care of managing which port to send requests on for you.

The concept and usage of `config.src.yaml` as a configuration file for tests is best explained in [this guide](../http/configure.md).

For basic behavior, this test harness is suitable. If an application is using the ORM or OAuth 2.0 features of Aqueduct, it should also handle provisioning a temporary database and inserting client identifiers and their scope. (Note: if you create an application using the `db` or `db_and_auth` templates, the test harness is already configured in the following ways.)

### Configuring a Database for Tests

It is important that you fully control the data the application is using during testing, otherwise you may not be isolating and verifying the appropriate behavior. Aqueduct's testing strategy is to create all the tables for your application's database and seed them with data before a test, and then drop those tables at the end of a test. Because Aqueduct can build your data model as tables in a database, this behavior is effectively free.

A test harness for an ORM application should have a method that creates a *temporary* `PersistentStore` and uploads the application's data model.

```dart
class TestApplication {
  ...
  static Future createDatabaseSchema(ManagedContext context) async {
    var builder = new SchemaBuilder.toSchema(
        context.persistentStore,
        new Schema.fromDataModel(context.dataModel),
        isTemporary: true);

    for (var cmd in builder.commands) {
      await context.persistentStore.execute(cmd);
    }
  }
}
```

This method should be invoked within `TestApplication.start`, right after the application is started.

```dart
Future start() async {
  Controller.letUncaughtExceptionsEscape = true;
  application = new Application<FoobarChannel>();
  application.options.port = 0;
  application.options.configurationFilePath = "config.src.yaml";

  await application.test();

  await createDatabaseSchema(ManagedContext.defaultContext);

  client = new TestClient(application);
}
```

Notice that the `ManagedContext.defaultContext` will have already been set by the application's `ApplicationChannel`.

After a test is executed, the test database should be cleared of data so that none of the stored data test leaks into the next test. Because starting and stopping an application isn't a cheap operation, it is often better to simply delete the contents of the database rather than restart the whole application. This is why the flag `isTemporary` in `SchemaBuilder.toSchema` matters: it creates *temporary* tables that only live as long as the database connection. By simply reconnecting to the database, all of the tables and data created are discarded. Therefore, all you have to do is close the connection and add the database schema again.

Here's a method to add to a test harness to do that. (Note that a connection is always reopened anytime a persistent store attempts to execute a query.)

```dart
Future discardPersistentData() async {
  await ManagedContext.defaultContext.persistentStore.close();
  await createDatabaseSchema(ManagedContext.defaultContext);
}
```

This method gets invoked in the `tearDown` of your tests. It runs after each test.

```dart
import 'harness/app.dart';

void main() {
  var app = new TestApplication();
  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });

  tearDown(() async {
    await app.discardPersistentData();
  });
}
```

### Configuring OAuth 2.0 for Tests

An application that uses types like `AuthServer` and `Authorizer` must have valid client IDs for testing. These are best set up in a test harness. Here's a method to add to a test harness to create client identifiers when using `ManagedAuthDelegate`:

```dart
static Future<ManagedAuthClient> addClientRecord(
    {String clientID: "default",
    String clientSecret: "default"}) async {
  var salt;
  var hashedPassword;
  if (clientSecret != null) {
    salt = AuthUtility.generateRandomSalt();
    hashedPassword = AuthUtility.generatePasswordHash(clientSecret, salt);
  }

  var clientQ = new Query<ManagedAuthClient>()
    ..values.id = clientID
    ..values.salt = salt
    ..values.hashedSecret = hashedPassword;
  return clientQ.insert();
}
```

This method is invoked doing application startup and again after persistent data is discarded. Additionally, when creating a test client, it often makes sense to set the its default client ID and secret to some default client identifier:

```dart
client = new TestClient(application)
  ..clientID = DefaultClientID
  ..clientSecret = DefaultClientSecret;
```
