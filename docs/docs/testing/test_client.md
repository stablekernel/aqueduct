# Verify Requests with TestClient

Setting up a [Test Harness](harness.md) is required for testing Aqueduct applications. Once a test harness is set up, tests are comprised of issuing HTTP requests to the application, verifying responses, and sometimes checking external data sources for desired changes.

HTTP requests are issued through an instance of `TestClient`. A `TestApplication` harness has a `client` property of this type. Starting a `TestApplication` configures the `TestClient` so that its requests go to your application. There are three execution methods on `TestClient`, the most basic being `request`:

```dart
test("Test that this endpoint returns 200", () async {
  var response = app.client.request("/endpoint").get();
  expect(response, hasStatus(200));
});
```

The `request` method creates a new instance of `TestRequest`. A `TestRequest` is an object that represents an HTTP request, and it has execution methods like `get`, `post`, etc. as well as properties for setting headers, query parameters and an HTTP body. Here's a configured `TestRequest`:

```dart
app.client.request("/endpoint")
  ..queryParameters = {"q": 1},
  ..headers = {"Header": "value"}
  ..body = "...";
```

Query parameter values are URL string encoded.

There are conveniences for adding authorization info:

```dart
app.client.request("/endpoint")
  ..setBasicAuthorization("username", "password");

app.client.request("/endpoint")
  ..bearerAuthorization(bearerToken);
```

There are also conveniences for setting the body of the request. The following code both encodes the body argument as JSON and sets the content-type header to `application/json`:

```dart
app.client.request("/endpoint")
  ..json = {"key": "value"};
```

A similar property named `formData` exists for `x-www-form-urlencoded` bodies.

The other two variants of `request` are `clientAuthenticatedRequest` and `authenticatedRequest`. A `clientAuthenticatedRequest` includes a Basic Authorization header, while an `authenticatedRequest` includes a Bearer Authorization header.

A `TestClient` has default values for both bearer and basic authorization headers. For example, the test harness sets the default credentials for a `clientAuthenticatedRequest` to the testing client ID. When creating a `clientAuthenticatedRequest` and not specifying the client ID and secret, those values are used:

```dart
var request = app.client.clientAuthenticatedRequest("/endpoint");
// request's authorization header is: Basic base64(com.aqueduct.test:kilimanjaro)
```

The default can be replaced with optional arguments:

```dart
var request = app.client.clientAuthenticatedRequest(
  "/endpoint", clientID: "foo", clientSecret: "bar");
```

The same goes for `authenticatedRequest`, except that there is no default value to begin with. It often makes sense to create a 'user' during the setup of tests and then set the default bearer token to that user's granted token:

```dart
setUp(() async {
  await app.start();

  var registerRequest = app.client.clientAuthenticatedRequest("/register")
    ..json = {"email": "fred@fred.com", "password": "bob"};
  var registerResponse = await registerRequest.post();
  app.client.defaultAccessToken = registerResponse.asMap["access_token"];
});

test("With default bearer token", () async {
  var response = await app.client.authenticatedRequest("/endpoint").get();
  ...
});

test("With another bearer token", () async {
  var response = await app.client
    .authenticatedRequest("/endpoint", accessToken: "someOtherToken").get();
  ...
});

```

It's often useful to move this code into a method in the `TestApplication` itself.

### Matching Responses

Tests for an Aqueduct application usually involve sending a request and verifying the response is what you expected. When a `TestRequest` is executed with a method like `get`, a `TestResponse` is returned. A `TestResponse` can be cherry-picked for information to validate, but there are also special test matchers in the `aqueduct/test` library. (This library is exported from the test harness file that ships with applications created by `aqueduct create`.)

An example of a test that verifies a 200 status code response looks like this:

```dart
test("Get 200", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasStatus(200));
});
```

`hasStatus` is an Aqueduct matcher. It verifies that a `TestResponse`'s status code is 200. It's more likely that you are interested in verifying the body of a response using the `hasResponse` matcher. This matcher checks everything about a response.

```dart
test("Get 200 with key value pair", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, {
      "key": "value"
  }));
});
```

This will validate that not only does the response have a 200 status code, but its body - after decoding - is a `Map` that contains `key: value`. A `TestResponse` automatically decodes its HTTP body according to the Content-Type response header.

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

The body of a `TestResponse` can also be accessed via `body`, `asMap`, and `asList`.

```dart
test("Get 200 with more than five key value pairs", () async {
  var response = await app.client.request("/endpoint").get();
  expect(response, hasResponse(200, everyElement({
      "count": greaterThan(1)
  })));

  expect(response.asList, hasLength(greaterThan(5)));
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

### Verifying Other Information

Sometimes, the response to a request doesn't have all of the information that needs to be verified. For example, a request that triggers the Aqueduct application to send a request to some other server can't always be verified through the response. The `MockHTTPServer` makes it easy to check if the request triggered another request.

```dart
setUp(() async {
  ...
  mockServer = new MockHTTPServer(4000);
  await mockServer.open();
});

tearDown(() async {
  await mockServer.close();
});

test("Sends message to Google", () async {
  var response = await app.client.request("/do_google_stuff").get();

  var outRequest = await mockServer.next();
  expect(outRequest.method, "POST");
  expect(outRequest.path, "/search");
});
```

A `MockHTTPServer` always listens on localhost. You can specify the port. In practice, you will configure remote services like these through a configuration file. If in production, this outgoing request should go to `https://google.com`, the `config.yaml` file would have that value:

```
google:
  url: https://google.com
```

But in the `config.yaml.src` file that drives the tests, this configuration value would point back locally to a port of your choosing:

```
google:
  url: http://localhost
  port: 4000
```      

You may also want to query the database a test application is working with. You can access any property of the application's `RequestSink` - including its `ManagedContext` - through the `TestApplication`.

```dart
test("ensure we hashed the password", () async {
  var response = await (app.client.request("/register")
    ..json = {"email": "a@b.com", "password": "foo"}).get();

  var passwordQuery = new Query<User>(app.mainIsolateSink.context)
    ..where.email = whereEqualTo("a@b.com");
  var user = await passwordQuery.fetchOne();
  expect(AuthUtility.generatePasswordHash("foo", user.salt), user.password);
});
```
