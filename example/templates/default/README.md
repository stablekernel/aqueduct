# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).


## Running Tests

To run all tests for this application, run the following command in this directory:

```
pub run test -j 1
```

Tests will be run using the configuration file `config.yaml.src`. This file should contain all test configuration values and remain in source control. This `config.yaml.src` file is the 'template' for `config.yaml` files living on deployed servers. This allows tests to use a configuration file with the same layout as deployed instances and avoid configuration errors.

See the application test harness, `test/app/harness.dart`, for more details. This file contains a `TestApplication` class that can be set up and torn down for tests. It will create a temporary database that the tests run against. See examples of usage in the `_test.dart` files in `test/`.

See [Testing](https://aqueduct.io/docs/testing/overview).

## Deployment and Database Provisioning

Run Aqueduct applications with `aqueduct serve`.


## Creating API Documentation

In the project directory, run:

```bash
aqueduct document
```

This will print a JSON OpenAPI specification to stdout.
