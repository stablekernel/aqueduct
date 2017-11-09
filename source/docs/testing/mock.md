# Mocking External Services

An Aqueduct application often communicates with another server. For example, an application might make requests to the GitHub API to collect analytics about a team's workflow. When running automated tests, consuming the actual GitHub API isn't feasible - because GitHub will probably rate limit you and because the data being returned is constantly changing.

To solve this problem, you can create "mocks" of a service during testing. Aqueduct has two testing utilities for this purpose - `MockServer` and `MockHTTPServer` - in the `aqueduct/test` library.

## Using a MockHTTPServer

When testing your application, you send it requests using a `TestClient`. As part of the request handling logic, your application might issue requests to some other server. `MockHTTPServer` allows you to validate that the request your application sent was correct and gives you control what the responses are to those requests. For example, `githubMock` is an instance of `MockHTTPServer` in the following test, which ensures that the request was constructed correctly:

```dart
test("Will get correct user from GitHub", () async {
  var response =
    await app.client.authenticatedRequest("/github_profile/fred").get();

  var requestSentByYourApplicationToGitHub = await githubMock.next();
  expect(requestSentByYourApplicationToGitHub.method, "GET");
  expect(requestSentByYourApplicationToGitHub.path, "/users/search?name=fred");
});
```

In the above code, we are expecting that anytime the request `GET /github_profile/fred` is sent to your application, that it turns around and searches for a user in GitHub's API. This test ensures that we have correctly translated our request to a request to be made to the GitHub API. If no request was made - because of a programmer error - this test would fail because the `Future` returned from `githubMock.next()` would never complete. There is no next request, because none was ever delivered!

By default, any request sent to a `MockHTTPServer` is a 200 OK Response with an empty body. You may change this behavior by queuing responses in a mock server.

```dart
test("Will get correct user from GitHub", () async {
  githubMock.queueResponse(new Response.ok({"id": 1, "name": "fred"}));

  var response =
    await app.client.authenticatedRequest("/github_profile/fred").get();
  expect(response, hasResponse(200, partial({
    "id": 1,
    "name": "fred"
  })))
});
```

In the above code, `queueResponse` adds a 200 OK Response to the mock server queue with a specific body. The mock server will send that response for the next request it receives. In the implementation of `/github_profile/fred`, your application sends a `GET /users/search?name=fred` to the GitHub API - except the GitHub API is your mock server, and it returns the response you queued instead. Thus, the queued up response is the expected response of the GitHub API.

After the request completes, the response is removed from the queue and subsequent responses will go back to the default. You may queue as many responses as you like. You may also simulate a failed request - one that never gets a response - like so:

```dart
mockServer.queueResponse(MockHTTPServer.mockConnectionFailureResponse);
```

You may also subclass `MockHTTPServer` and override its `open` method to add logic to determine the response. Please see the implementation of `MockHTTPServer.open` for more details.

## Configuring a MockHTTPServer

A `MockHTTPServer` is created when setting up tests. It must be closed when tearing down tests. If you use the same mock server to across all tests (e.g., open it in `setUpAll`), make sure to clear it after each test:

```dart
import 'package:aqueduct/test.dart';

void main() {
  var mockServer = new MockHTTPServer(4000);

  setUpAll(() async {
    await mockServer.open();
  });

  tearDownAll(() async {
    await mockServer.close();
  });

  tearDown(() async {
    mockServer.clear();
  });
}
```

An instance of `MockHTTPServer` listens on localhost on a specific port. An application that makes testable external service requests should provide the base URI for those services in a configuration file. The URI for that service in the [configuration file used during testing](../http/configure.md) should point at localhost and a specific port. For example, if a deployed `config.yaml` file has the following key-values:

```
github:
  baseURL: https://api.github.com/  
```

Then `config.src.yaml` would have:

```
github:
  baseURL: http://localhost:4000/
```

Your application reads this configuration file and injects the base URL into the service that will execute requests.

```dart
class AppConfigurationItem extends ConfigurationItem {
  AppConfigurationItem(String fileName) : super.fromFile(fileName);

  APIConfiguration github;
}

class AppApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    var config = new AppConfigurationItem(options.configurationFilePath);

    githubService = new GitHubService(baseURL: config.github.baseURL);
  }
}
```

Note that `APIConfiguration` is an existing type and is meant for this purpose.

Also note that the testing strategy for database connections is *not* to use a mock but to use a temporary, local database that is set up and torn down during tests. This is possible because you own the data model generating code - whereas you probably don't have access to an external service's development API.
