# Testing Applications That Use ORM and OAuth 2.0

This document describes how to set up your test code to test applications that use the ORM and OAuth 2.0. These types of applications require extra initialization steps, e.g. set up a test database.

## Testing Applications That Use the ORM

Aqueduct's ORM uses PostgreSQL as its database. Before your tests run, Aqueduct will create your application's database tables in a local PostgreSQL database. After the tests complete, it will delete those tables. This allows you to start with an empty database for each test suite as well as control exactly which records are in your database while testing, but without having to manage database schemas or use an mock implementation (e.g., SQLite).

!!! warning "You Must Install PostgreSQL Locally"
        On macOS, [Postgres.app](https://postgresapp.com) is a simple, self-contained PostgreSQL instance that you can run as a normal application. (See [PostgreSQL installation for other platforms](https://www.postgresql.org/download/).)

### Local Database for Tests

The same database is reused for testing all of your applications. You only have to create this database once per development machine, or when running in a CI tool like TravisCI. From PostgreSQL's prompt, run:

```sql
CREATE DATABASE dart_test;
CREATE USER dart WITH createdb;
ALTER USER dart WITH password 'dart';
GRANT all ON DATABASE dart_test TO dart;
```

A database configuration in your application's `config.yaml.src` must match the following:

```
username: dart
password: dart
host: localhost
port: 5432
databaseName: dart_test
```

Your application, when run with a subclass of `TestHarness<T>`, will configure its database connection to connect to the local test database. You must mixin `TestHarnessORMMixin` with your test harness and invoke `resetData` by overriding `onSetUp`. You may also override `seed` to insert test data into the database.

```dart
class Harness extends TestHarness<AppChannel> with TestHarnessORMMixin {
  @override
  ManagedContext get context => channel.context;

  @override
  Future onSetUp() async {
    await resetData();
  }

  @override
  Future seed() async {
    /* insert some rows here */
  }
}
```

!!! tip "Seeding Data"
          You should only seed static data in the `seed` method; this may include things like categories or country codes that cannot be changed during runtime. Data that is manipulated for specific test cases should be invoked in a test `setUp` callback or the test itself.


### Local Database for Running an Application

A database separate from the test database should be used for *running* an application locally. You can create a database locally by running `psql` to open a PostgreSQL terminal and run the following commands:

```
CREATE DATABASE my_app_name;
CREATE USER my_app_user WITH PASSWORD 'mypassword';
GRANT ALL ON DATABASE my_app_name TO my_app_user;
```

Add your schema to the local database by generating and executing migration scripts:

```
aqueduct db generate
aqueduct db upgrade --connect postgres://my_app_user:mypassword@localhost:5432/my_app_name
```

## Testing Applications That Use OAuth 2.0

Applications that use OAuth 2.0 should mixin `TestHarnessAuthMixin`. This mixin adds methods for registering a client identifier and authenticating a user. Both methods return an `Agent` with default headers with authorization information for the client identifier or user.

Most often, you use `package:aqueduct/managed_auth` for an ORM-driven OAuth2 delegate. You must also mixin `TestHarnessORMMixin` when using this mixin.

```dart
class Harness extends TestHarness<AppChannel> with TestHarnessAuthMixin<AppChannel>, TestHarnessORMMixin {
  @override
  ManagedContext get context => channel.context;

  @override
  AuthServer get authServer => channel.authServer;

  Agent publicAgent;

  @override
  Future onSetUp() async {    
    await resetData();
    publicAgent = await addClient("com.aqueduct.public");
  }

  Future<Agent> registerUser(User user, {Agent withClient}) async {
    withClient ??= publicAgent;

    final req = withClient.request("/register")
      ..body = {"username": user.username, "password": user.password};
    await req.post();

    return loginUser(withClient, user.username, user.password);
  }
}
```
