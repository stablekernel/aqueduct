# Testing in Aqueduct

From the ground up, Aqueduct is built to be tested. In practice, this means two things:

- A deployed Aqueduct application has zero code differences from an Aqueduct application under test.
- There are helpful utilities for writing tests in Aqueduct.

## How Tests are Written

An Aqueduct test suite starts your application with a configuration file specifically built for a test instance of your application. You write test cases that verify the responses of requests sent to this application. Sometimes, you might reach into your application's services to validate that an intended side-effect was triggered. For example, you might ensure that after a request was executed, a row was added to a database table.

A `TestHarness<T>` is a type from `package:aqueduct_test` that handles the initialization of your application under test. It is often subclassed to add application-specific startup tasks, like seeding a database with test users or adding OAuth 2.0 clients. A test harness is installed at the beginning of your test's `main` function.

```dart
void main() {
  final harness = new TestHarness<MyApplicationChannel>()..install();

  test("GET /endpoint returns 200 and a simple object", () async {
    final response = await harness.agent.get("/endpoint");
    expectResponse(response, 200, body: {"key": "value"});
  });
}}
```

When `TestHarness.install` is invoked, it installs two callbacks from `package:test` that will start your application in 'test mode' when the tests start, and stop it after the tests complete. An application running in 'test mode' creates a local HTTP server and instantiates your `ApplicationChannel` *on the same isolate as your tests are running on*. This allows you to reach into your application channel's services to add test expectations on the state that the services manage.

When your application is started in this way, its options have some default values:

- the application listens on a random port
- the `configurationFilePath` is `config.src.yaml`

The `config.src.yaml` file must have the same structure as your deployment configurations, but values are substituted with test control values. For example, database connection configuration will point at a local test database instead of a production database. For more details on configuring an application, see [this guide](../http/configure.md).

!!! note "Harness Install"
    The `install` method calls `setUpAll` and `tearDownAll` from `package:test` to start and stop your application. You can manually start and stop your application by invoking `TestHarness.setUp` and `TestHarness.tearDown`.

!!! note "Uncaught Exceptions when Testing"
    A test harness configures the application the let uncaught exceptions escape so that they trigger a failure in your test. This is different than when running an application normally, where all exceptions are caught and send an error response to the HTTP client.

### Using a TestHarness Subclass

Applications created with `aqueduct create` include a `TestHarness<T>` subclass that can be modified for your application's specific needs (where `T` is your application channel subclass). This file that contains this subclass is located in `test/harness/app.dart`. A simple test harness subclass looks like this:

```dart
class Harness extends TestHarness<WildfireChannel> {
  @override
  Future beforeStart() async {
    // add initialization code that will run prior to the test application starting
  }

  @override
  Future afterStart() async {
    // add initialization code that will run once the test application has started
  }
}
```

Use `beforeStart` to configure your test environment before your application starts. For example, you might start a `MockHTTPServer` that emulates another system your application integrates with, or you might set an environment variable that your application should read when it starts.

Use `afterStart` to configure your test environment after the application starts. This step is useful because you may use your application's services to perform initialization. For example, you might create all of your database tables by executing queries with your `ManagedContext`. (This is a common task, see [harness mixins](mixins.md) for a mixin that takes care of this.)

Add initialization code that configures your application prior to it starting in `beforeStart`. This would include code that modifies `ApplicationOptions` are sets up external services. After your application has started, you can add initialization code that configures application state, like adding OAuth 2.0 clients that will be used for testing or seeding a database with data. This initialization code is performed in `afterStart`.

You often add methods to your harness subclass for common tasks across tests. For example, if your application requires an authorized user, it makes sense to have a method that can add and authenticate a new user so that test requests are executed on behalf of that user. (This is a common task, see [harness mixins](mixins.md) for a mixin that takes care of this.)

## Using an Agent to Execute Requests

A `TestHarness<T>` has an `agent` property that is used to execute requests against the application being tested. An `Agent` has methods like `get` and `post` to execute requests and return a response object that can be validated. Its usage looks like this:

```dart
test("After POST to /thing, GET /thing/:id returns created thing", () async {
  final postResponse = await harness.agent.post("/thing", body: {"key": "value"});
  expectResponse(postResponse, 200);

  final thingId = postResponse.body.as<Map>()["id"];
  final getResponse = await harness.agent.get("/thing/$thingId");
  expectResponse(getResponse, 200, body: {
    "id": thingId,
    "key": "value"
  });
});
```

Most requests can be configured and executed in methods like `TestHarness.get` and `TestHarness.post`. For additional configuration options, use `TestHarness.request` to create a request object that can be further customized by its properties:

```dart
final request = harness.agent.request("/endpoint")
  ..headers["X-Header"] = "Value";
```

When a request includes a body, the body is encoded according to the content-type of the request (defaults to JSON). The encoding behavior is provided by `CodecRegistry`, the same type that manages encoding and decoding for your application logic. When adding a body to a test request, you provide the unencoded value (a Dart `Map`, for example) and it is encoded into the correct value (a JSON object, for example). On the inverse side, when validating a response body, the body is already decoded to a Dart type prior to your test code receiving the response.

!!! note "Codecs and CodecRegistry"
    Your tests will run on the same isolate as your application. Whatever codecs have been registered in the codec repository by your application are automatically made available to the code that encodes and decodes your tests requests. You don't have to do anything special to opt-in to non-default codecs.

### Agents Add Default Values to Requests

An `Agent` has defaults values that it applies to requests from it. These values include headers and the request body content-type. For example, you might want all requests to have an extra header value, without having to write the code to add the header for each request.

The default agent of a harness creates requests that have a `application/json` `contentType`. Additional agents can be created for different sets of defaults.

This is especially useful when testing endpoints that require authorization, where credentials need to be attached to each request. This is a common enough task that there are [harness mixins](mixins.md) that make this task easier.

## Writing Test Expectations

After an agent executes a request, you write test expectations on its response. These expectations include verifying the status code, headers and body of the response are the desired values. Expectations are set by applying matchers to the properties of a response. For example:

```dart
test("GET /foo returns 200 OK", () async {
  final response = await harness.agent.get("/foo");

  expect(response.statusCode, 200);
  expect(response, hasHeaders({"x-timestamp": greaterThan(DateTime(2020))}));
  expect(response, hasBody(isNull));
});
```

Validating response headers and bodies can be more complex than validating a status code. The `hasBody` and `hasHeaders` matchers make expectations on the response headers and body easier to write.

The `hasHeaders` matcher takes a map of header names and values, and expects that the response's headers contains a matching header for each one in the map. The value may be a `String` or another `Matcher`. The response can have more headers than expected - those headers are ignored. If you want to exactly specify all headers, there is an optional flag to pass `hasHeaders`.

The `hasBody` matcher takes any object or matcher that is compared to the *decoded* body of the response. The body is decoded according to its content-type prior to this comparison. For example, if your response returns a JSON object `{"key": "value"}`, this object is first decoded into a Dart `Map` with the value `{'key': 'value'}`. The following matchers would all be true:

```dart
// exact match of Dart Map
expect(response, hasBody({'key': 'value'}));

// a map that contains a key whose value starts with 'v'
expect(response, hasBody({'key': startsWith('v')}));

// a map that contains the key 'key'
expect(response, hasBody(containsKey('key')));

// a map with one entry
expect(response, hasBody(hasLength(1)));
```

For large response bodies where you have other test coverage, you may only want to set expectations for a few values. For example, you might have a map with 50 keys, but all you care about it making sure that `status='pending'`. For this, there is a `partial` map matcher. It behaves similar to `hasHeaders` in that it only checks the keys you provide - any other keys are ignored. For example:

```dart
// Just ensure the body contains an object with at least status=pending, version>1
expect(response, hasBody(partial({
  "status": "pending",
  "version": greaterThan(1)
})));
```

When using `partial`, you can also ensure that a map doesn't have a key with the `isNotPresent` matcher.

```dart
test("Get 200 that at least have these keys", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, partial({
    "key3": isNotPresent
  })));
});
```

This ensures that `key3` is not in the map. This is different than verifying `key3: null`, which would be true if `key3`'s value was actually the null value. See the [API Reference](https://www.dartdocs.org/documentation/aqueduct/latest/aqueduct.test/aqueduct.test-library.html) for `aqueduct/test` for more matchers.

### Verifying Side Effects

For requests that are not idempotent (they change data in some way), you must also verify the state of the data has changed correctly after the request. This is often done by sending another request your application handles to get the updated data. For example, after you create an employee with `POST /employees`, you verify the employee was stored correctly by expecting `GET /employees/:id` has the same data you just sent it.

Sometimes, the expected changes are not accessible through your API. For example, let's say that creating a new employee adds a record to an auditing database, but this database is not accessible through a public API. When testing, however, you would want to ensure that record was added to the database. You can access your application's services (like its database connection) in your tests through `TestHarness.channel`. For example, you might execute a `Query<T>` against your application's test database:

```dart
test("POST /employees adds an audit log record", () async {
  final response = await harness.agent.post("/employees", body: {
    "name": "Fred"
  });

  expect(response, hasStatus(202));

  final context = harness.channel.context;
  final query = new Query<AuditRecord>(context)
    ..where((record) => record.user.id).equalTo(response.body.as<Map>()['id']);
  final record = await query.fetchOne();
  expect(record, isNotNull);
});
```

Anything the `ApplicationChannel` can access, so too can the tests.

## Further Reading

For testing applications that use OAuth 2.0 or the ORM, see the guide on [mixins](mixins.md) for important behavior.
