# wildfire

## Running the Application Locally

Run `aqueduct serve` from this directory to run the application. For running within an IDE, run `bin/main.dart`.

You must have a `config.yaml` file that has correct database connection info, which should point to a local database. To configure a database to match your application's schema, run the following commands:

```
# if this is a new project, run db generate first
aqueduct db generate
aqueduct db upgrade --connect postgres://user:password@localhost:5432/wildfire
```

You must also configure OAuth 2.0 Client identifiers in this database.

```
aqueduct auth add-client --id com.local.test \
    --secret mysecret \
    --connect postgres://user:password@localhost:5432/wildfire
```

To generate a SwaggerUI client, run `aqueduct document client`.

## Running Application Tests

Tests are run with a local PostgreSQL database named `dart_test`. If this database does not exist, create it from your SQL prompt:

CREATE DATABASE dart_test;
CREATE USER dart WITH createdb;
ALTER USER dart WITH password 'dart';
GRANT all ON DATABASE dart_test TO dart;


To run all tests for this application, run the following in this directory:

```
pub run test
```

The default configuration file used when testing is `config.src.yaml`. This file should be checked into version control. It also the template for configuration files used in deployment.

## Deploying an Application

See the documentation for [Deployment](https://aqueduct.io/docs/deploy/).
