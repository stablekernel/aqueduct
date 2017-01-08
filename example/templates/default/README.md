# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

If you have not yet, run:

```
aqueduct setup
```

See [Getting Started](https://stablekernel.github.io/aqueduct/deploy/getting_started.html)

## Routes

See configured routes in `lib/wildfire_sink.dart`.

## Authentication/Authorization

This project uses OAuth 2.0. See the [Deployment Guides](http://stablekernel.github.io/aqueduct/deploy/overview.html) for provisioning the database to hold auth information and inserting OAuth 2.0 client IDs.

Routes are pre-configured for the resource owner password flow (`/auth/token`) and the authorization code flow (`/auth/code` and `/auth/token`).

## Running Tests

To run all tests for this application, run the following command in this directory:

```
pub run test -j 1
```

Tests will be run using the configuration file `config.yaml.src`. This file should contain all test configuration values and remain in source control. This `config.yaml.src` file is the 'template' for `config.yaml` files living on deployed servers. This allows tests to use a configuration file with the same layout as deployed instances and avoid configuration errors.

See the application test harness, `test/app/harness.dart`, for more details. This file contains a `TestApplication` class that can be set up and torn down for tests. It will create a temporary database that the tests run against. See examples of usage in the `_test.dart` files in `test/`.

See [Getting Started](https://stablekernel.github.io/aqueduct/deploy/getting_started.html) and [Testing](https://stablekernel.github.io/aqueduct/testing/overview.html).

## Deployment and Database Provisioning

See the [Deployment Guides](http://stablekernel.github.io/aqueduct/deploy/overview.html)

## Creating API Documentation

Run the following script from this directory to generate an OpenAPI 2.0 JSON specification file for your web server:

```
dart bin/document.dart
```

This will print a JSON OpenAPI specification to stdout.
