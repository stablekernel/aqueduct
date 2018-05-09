## Tasks

Aqueduct applications can be run, tested, debugged and profiled.

You create a subclass of `TestHarness<T>` in your application's `test/` directory. For each test suite, you install this harness to start and stop your application in 'test' mode. A test harness runs your application like a live application.

You use `Agent` objects to send HTTP requests to your application under test. Agents add default information to all of their requests, like authorization information. You use test matchers like `hasResponse` or `hasStatus` to validate the response your application sends for a given request.

You provide mock services for external services that your application communicates with. These are often driven by the contents of a configuration file. (By convention, a configuration file for tests is named `config.src.yaml`.) You may also create mock services with `MockHTTPServer` to use during testing.

## Guides

- [Best Practices for Aqueduct Development](best_practices.md)
- [Using a Local Database](database.md)
- [Developing Client Applications](clients.md)
- [Using the Debugger and Profiling](debugger.md)
- [Writing Tests](tests.md)
- [Use Mock Services](mock.md)
