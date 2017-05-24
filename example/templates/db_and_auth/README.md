# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

If you have not yet, run:

```
aqueduct setup
```

See [Getting Started](https://aqueduct.io/docs/)

## Notes

Files declaring an instance of `ManagedObject` must be exported from `lib/wildfire_model.dart`.

See configured routes in `lib/wildfire_sink.dart`.

To disable logging during tests, set `logging:type:` to `off` in `config.yaml.src`. To re-enable, set to `console`.

## Authentication/Authorization

This project uses OAuth 2.0. See the [Deployment Guides](http://aqueduct.io/docs/deploy/overview) for provisioning the database to hold auth information and inserting OAuth 2.0 client IDs.

Routes are pre-configured for the resource owner password flow (`/auth/token`) and the authorization code flow (`/auth/code` and `/auth/token`).

## Running Tests

To run all tests for this application, run the following command in this directory:

```
pub run test -j 1
```

Tests will be run using the configuration file `config.yaml.src`. This file should contain all test configuration values and remain in source control. This `config.yaml.src` file is the 'template' for `config.yaml` files living on deployed servers. This allows tests to use a configuration file with the same layout as deployed instances and avoid configuration errors.

See the application test harness, `test/app/harness.dart`, for more details. This file contains a `TestApplication` class that can be set up and torn down for tests. It will create a temporary database that the tests run against. See examples of usage in the `_test.dart` files in `test/`.

See [Testing](https://aqueduct.io/docs/testing/overview).

## Deployment and Database Provisioning

Run Aqueduct applications with `aqueduct serve`. This application connects to a database and requires a configuration file. See the [Deployment Guides](http://aqueduct.io/docs/deploy/overview/) for configuring databases.

## Logging and Configuration

The configuration file currently requires an entry for `database:` and `logging:`.

Logs can be sent to stdout or to a rotating file. See the behavior of `LoggingConfiguration` and `WildfireSink.initializeApplication` in `lib/wildfire_sink.dart` for possible configuration values.

See [safe_config](https://pub.dartlang.org/packages/safe_config) for more details on configuration.

## Creating API Documentation

In the project directory, run:

```bash
aqueduct document
```

This will print a JSON OpenAPI specification to stdout.
