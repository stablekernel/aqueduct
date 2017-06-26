## Tasks

Aqueduct applications can be run, tested, debugged and profiled.

Aqueduct tests start the the application when they are setting up. The application connects to a temporary, local database that discards its data when a test (or series of tests) completes. Requests are issued in tests with a `TestClient` that makes configuring requests simple. Hamcrest-style matchers validate request responses and can be used alongside the official Dart test package matchers.

## Guides

- [Best Practices for Aqueduct Development](best_practices.md)
- [Developing Client Applications](clients.md)
- [Using the Debugger](debugger.md)
- [Writing Tests](tests.md)
- [Use Mock Services](mock.md)
- [Using a Test Harness](harness.md)
- [Executing Requests and Validating Responses](test_client.md)
