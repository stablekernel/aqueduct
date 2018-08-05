# Testing Applications That Use ORM and OAuth 2.0



Aqueduct's ORM uses PostgreSQL as its database. To run the application or its automated tests locally, you must have PostgreSQL installed locally. On macOS, [Postgres.app](https://postgresapp.com) is a simple, self-contained PostgreSQL instance that you can run as a normal application. (See [PostgreSQL installation for other platforms](https://www.postgresql.org/download/).)

## Local Database for Tests

An application running automated tests defaults to connecting to a database with the following configuration:

```
username: dart
password: dart
host: localhost
port: 5432
databaseName: dart_test
```

Once PostgreSQL has been installed locally, you may create a database user and database that matches this connection info by running the following command:

```
aqueduct setup
```

Aqueduct tests create a temporary database schema that matches your application schema in the `dart_test` database. The tables and data in this database are discarded when the tests complete. For this reason, no other tables should be created in this database to avoid conflicts with tests. This default behavior of Aqueduct tests is provided by a [test harness](tests.md).

## Local Database for Running an Application

A database separate from the test database should be used for *running* an application locally. You can create a database locally by running `psql` to open a PostgreSQL terminal and run the following commands:

```
CREATE DATABASE my_local_app_db;
CREATE USER my_local_app_user WITH PASSWORD 'mypassword';
GRANT ALL ON DATABASE my_local_app_db TO my_local_app_user;
```

Add your schema to the local database by generating and executing migration scripts:

```
aqueduct db generate
aqueduct db upgrade --connect postgres://my_local_app_user:mypassword@localhost:5432/my_local_app_db
```

## Use Local Configuration Files

Use [configuration files](../http/configure.md) to manage which database an application connects to. This may or may not be checked into source control, depending on a team's preference. Control which file is loaded with command-line options to `aqueduct serve` or the `bin/main.dart` script:

```
aqueduct serve -c local.yaml
```

## Have Scripts to Provision Based on Scenarios

It is often the case that you will want to have a certain set of data in an local database for the purpose of testing a client application. Create `bin` scripts to provision the database and add the desired data. For example, you might have a script named `bin/ios_integration.dart` that re-provisions a database and inserts data into it using `Query<T>` instances and the `ManagedObject<T>`s declared in your application.

```dart
import 'dart:io';
import 'package:myapp/myapp.dart';

Future main() async {
  await provisionDatabase();

  var defaultUser = new User(...);
  await Query.insertObject(context, defaultUser);
  ...
}

Future provisionDatabase() async {
  var commands = [
    "CREATE DATABASE local_app;",
    "CREATE USER local_user WITH PASSWORD 'local';",
    "GRANT ALL ON DATABASE local_app TO local_user;"
  ];

  await Future.forEach(commands, (cmd) {
    List<String> args = ["-c", cmd, "-U", grantingUser];
    return Process.run("psql", args, runInShell: true);
  });
}
```
