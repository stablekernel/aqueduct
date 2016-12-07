# wildfire

An application built with [aqueduct](https://github.com/stablekernel/aqueduct).

## First Time Setup

If you have not yet, run:

```
aqueduct setup
```

## Running Tests

Run the following command in this directory to run all of the tests:

```
pub run test -j 1
```

Aqueduct tests will start an instance of your application, execute HTTP requests against it, and then close the application. You must run the tests with option `-j 1` to ensure tests run synchronously. Otherwise, concurrently running test files will fail because they cannot listen for HTTP requests on the same port.

## Creating API Documentation

Run the following script from this directory to generate an OpenAPI 3.0 JSON specification file for your web server:

```
dart bin/document.dart
```

This will print a JSON OpenAPI specification to stdout.

## Generating the Database Schema

Configure the connection information for the database in `migrations/migration.yaml`. The specified username must have the privileges to create tables.
(The file `migrations/migration.yaml.src` is a template for `migrations/migration.yaml`.)

You may copy and edit the migration template file:

```
cp migrations/migration.yaml.src migrations/migration.yaml
```

Run the migration generation tool:

```
aqueduct db generate
```

You may review the migration in `migrations/00000001_Initial.migration.dart`. To add the schema to the database defined in `migrations/migration.yaml`, run the migration upgrade command:

```
aqueduct db upgrade
```

You may create subsequent migration files with `aqueduct db generate`. Note that at this time, only the first migration file is fully generated. You will have to manually write migration code for subsequent migrations. Use the following command to validate if migrations will result in the data model in your application:

```
aqueduct db validate
```

## Running wildfire

Ensure that a `config.yaml` file exists in this directory. (The file `config.yaml.src` is a template for `config.yaml`.)

You may copy and edit config template file:

```
cp config.yaml.src config.yaml
```

Now, you can run your server locally:

```
  dart bin/start.dart 
```
 
Give executable permissions for the application script:

```
chmod a+x wildfire
```

Then, start the server on a specific branch in your local git repository:

```
./wildfire start <optional_git_branch_name>
```

Deployment environments such as `staging` or `development` maintained on seperate can be easily used in your deployment pipeline for your project. 

> It is important to note that this application script downloads remote references and does a hard reset on that branch and is not suitable for your local environment. Instead just point use `dart bin\start.dart` locally
