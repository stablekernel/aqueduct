# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

This application is tested against a local PostgreSQL database. The test harness (`test/harness/app.dart`) creates database tables for each `ManagedObject` subclass declared in this application. These tables are discarded when the test completes.

The local database installation must have a database named `dart_test`, for which a user named `dart` (with password `dart`) has full privileges to.
The following command creates this database and user on a locally running PostgreSQL database:

```
aqueduct setup
```

See `test/identity_controller_test.dart` for an example of a test suite.

For more information, see [Getting Started](https://aqueduct.io/docs/)

## Notes

The data model of this application is defined by all declared subclasses of `ManagedObject`. Each of these subclasses is defined in a file in the `model` directory.

Routes and other initialization are configured in `lib/wildfire_sink.dart`.


## Authentication/Authorization

This application uses OAuth 2.0 and has endpoints (`/auth/token` and `/auth/code`) for supporting the resource owner and authorization code flows.

The test harness inserts OAuth 2.0 clients into the application's storage prior to running a test. See `test/harness/app.dart` for more details and `test/identity_controller_test.dart` for usage.

OAuth 2.0 clients are added to a live database with the `aqueduct auth` command. For example,

```
aqueduct auth add-client \
    --id com.wildfire.mobile
    --secret myspecialsecret
    --connect postgres://user:password@host:5432/wildfire
```


For more information and more configuration options for OAuth 2.0 clients, see [OAuth 2.0 CLI](https://aqueduct.io/docs/auth/cli/)

## Running Tests

To run all tests for this application, run the following command in this directory:

```
pub run test
```

Tests will be run using the configuration file `config.src.yaml`. This file should contain all test configuration values and remain in source control. This `config.src.yaml` file is the 'template' for `config.yaml` files living on deployed servers. This allows tests to use a configuration file with the same layout as deployed instances and avoid configuration errors.

See the application test harness, `test/app/harness.dart`, for more details. This file contains a `TestApplication` class that can be set up and torn down for tests. It will create a temporary database that the tests run against. It alos inserts OAuth 2.0 clients into this test database prior to running a test. See examples of usage in the `_test.dart` files in `test/`.

See [Testing](https://aqueduct.io/docs/testing/overview).

## Deployment and Database Provisioning

Run Aqueduct applications with `aqueduct serve`. This application connects to a database and requires a configuration file. See the [Deployment Guides](http://aqueduct.io/docs/deploy/overview/) for configuring databases.

## Configuration

The configuration file (`config.yaml`) currently requires an entry for `database:` which describes a database connection.

The file `config.src.yaml` is used for testing: it should be checked into source control and contain values for testing purposes. It should maintain the same keys as `config.yaml`.

## Creating API Documentation

In the project directory, run:

```bash
aqueduct document
```

This will print a JSON OpenAPI specification to stdout.
