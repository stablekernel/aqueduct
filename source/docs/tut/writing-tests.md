# 4. Configuration and Writing Tests

We will continue to build on the last chapter's project, `heroes`, by writing automated tests for it. We will also set up configurable environments for our application.

## Application Configuration

Right now, our application hardcodes its database connection information. This is bad because we want to use a different database when we're testing, running locally and running in production. It's also bad because we'd have to check our database password into version control.

We can create an configuration file to store values like database connection information, and use a different configuration file for each environment. The `heroes` application needs to be able to configure the username, password, host port and name of the database it uses. Open the file `config.yaml`, which is empty, and enter the following key-value pairs:

```yaml
database:
  host: localhost
  port: 5432
  username: heroes_user
  password: password
  databaseName: heroes
```

These are the same values we used in our application channel. We'll want to replace the hardcoded values with whatever values are in this file. In `lib/channel.dart`, declare a new class at the bottom of the file:

```dart
class HeroConfig extends Configuration {
  HeroConfig(String path): super.fromFile(File(path));

  DatabaseConfiguration database;
}
```

A `Configuration` subclass declares the expected properties of a configuration file. `HeroConfig` has one property named `database` - this just so happens to be the same name as the first key in `config.yaml`. A `DatabaseConfiguration` is a built-in configuration type that has properties for host, port, username, password and databaseName. We can load `config.yaml` into a `HeroConfig` because they have the same structure.

!!! tip "Invalid Configuration"
    If your configuration file and configuration object don't have a matching structure, an error will be thrown when your application starts and tell you which values are missing.

Let's load this configuration file and use its values to set up our database connection by replacing the `prepare` method in `lib/channel.dart`:

```dart
@override
Future prepare() async {
  logger.onRecord.listen(
      (rec) => print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

  final config = HeroConfig(options.configurationFilePath);
  final dataModel = ManagedDataModel.fromCurrentMirrorSystem();
  final persistentStore = PostgreSQLPersistentStore.fromConnectionInfo(
      config.database.username,
      config.database.password,
      config.database.host,
      config.database.port,
      config.database.databaseName);

  context = ManagedContext(dataModel, persistentStore);
}
```  

When our application starts, our channel has access to an `options` property that has the command-line arguments that started the application. By default, the value of `configurationFilePath` is `config.yaml` (it corresponds to `--config-path` in `aqueduct serve`). When `config.yaml` is read, its values are read into the `config` object and is used to configure our database connection.

Re-run your application and it'll work exactly the same as it did before - except now, we can substitute databases depending on how we run the application.

### Configuration Template

You shouldn't check `config.yaml` into version control because it contains sensitive information. However, it is important to check in a *configuration source file*. A configuration source file has the same structure as `HeroConfig`, but it has values for your test environment. It is used as a template for your deployed configuration files, and it is also used during automated testing.

!!! tip "Sensitive Information"
    Use a platform like Heroku or Kubernetes. You can store sensitive information in environment variables. You can read environment variables into a configuration file by using the variable's name with a `$` prefix as a value, e.g. `password: $DATABASE_PASSWORD`.

This filename defaults to `config.src.yaml`, and is currently empty in your project. Enter the following configuration into this file:

```dart
database:
  host: localhost
  port: 5432
  username: dart
  password: dart
  databaseName: dart_test
```  

This file has the expected structure, but has different values for the database information. In the next section, we'll use this configuration file to run our automated tests.

## Testing in Aqueduct

So far, we've tested our application by using a web application. This isn't a good way to test an application. A better way is to write automated test cases. An automated test case not only tests the code you are working on, but makes sure the code you've worked on the past continues to work as you make changes. A good development practice is to configure [TravisCI](https://travis-ci.com) to run all of your tests for every code change.

Because testing is so important, there is a package for writing Aqueduct application tests. In this chapter, we will use this package to make sure our hero endpoints are working correctly.

!!! note "package:aqueduct_test"
    The package `aqueduct_test` and `test` was already added to your `pubspec.yaml` file as a test dependency by the template generator.

In all Dart applications, tests are a Dart script with a `main` function. The `test` function registers a closure that contains expectations. That closure is run when you run your test suite, and the tests pass if all of your expectations are met. An example Dart test looks like this:

```dart
import 'package:test/test.dart';

void main() {
  test("1+1 = 2", () {
    // Expect that 1 + 1 = 2
    expect(1 + 1, equals(2));
  });
}
```

### Setting up your Development Environment

In `config.src.yaml`, we target the database `dart:dart@localhost:5432/dart_test`. This database is used by all Aqueduct applications for automated testing. When your application is tested, your application's tables are temporarily added to this database and then discarded after tests complete. This means that no data is stored in between test runs.

Create this database by running `psql` and enter the following SQL:

```sql
CREATE DATABASE dart_test;
CREATE USER dart WITH createdb;
ALTER USER dart WITH password 'dart';
GRANT all ON database dart_test TO dart;
```

!!! tip "dart_test Database"
    You only have to create this database once per machine, and in any continuous integration scripts. All of your Aqueduct applications will use this database for automated testing.

### Writing Your First Test

We will create a test suite to make sure that all hero endpoints return the right data, and make the right changes. Create a new file named `test/hero_controller_test.dart`.

!!! warning "Test Files Names and Locations"
    A test file must end in `_test.dart` and must be in the `test/` directory of your project, or it won't be run.

At the top of this file, import your application's *test harness* and enter the following `main` function:

```dart
import 'harness/app.dart';

void main() {
  final harness = Harness()..install();
}
```

A test harness is an object that starts and stops your application when running a test suite, as long as you call its `install` method. This harness can then send requests to your application, and you can expect that the response is correct. Add a test to the main function that makes sure we get back a 200 OK when we call `GET /heroes`:

```dart
void main() {
  final harness = Harness()..install();

  test("GET /heroes returns 200 OK", () async {
    final response = await harness.agent.get("/heroes");
    expectResponse(response, 200);
  });
}
```

A harness has an `Agent` that can send requests to the application it started. Methods like `get` and `post` take a path (and optionally headers and a body) and return a response object. This object is used in `expectResponse` to validate the status code and other values. Tests in Aqueduct are written in this way: make a request, expect that the response is intended.

Because our application makes database queries, we have to to upload our database schema to the test database before each test. Fortunately, this is something our test harness can also do. In `test/harness/app.dart`, mixin `TestHarnessORMMixin` and override two methods:

```dart
class Harness extends TestHarness<WildfireChannel> with TestHarnessORMMixin {
  @override
  ManagedContext get context => channel.context;

  @override
  Future onSetUp() async {
    await resetData();
  }
}
```

The mixin gives our harness the method `resetData`. This method deletes everything from the test database and uploads the schema in a pristine state. By calling this method in `onSetUp`, our test harness will reset data before each test.

Now, we can run this test by right-clicking on the `main` function in `hero_controller_test.dart` and selecting `Run tests in 'hero_controller_test.dart'`. A panel will appear that shows the results of your tests. You'll see a green checkmark next to the test in this panel to show that your test succeeded. If your test did not succeed, the reason will be printed to the console. If your test failed because of an error in your code, you will also be able to see the stack trace of the error.

!!! tip "Running Tests"
    You can also run all of your tests for an application by running `pub run test` from your project's directory. You can re-run a test with the green play button at the top right corner of the screen, or the keyboard shortcut associated with it (this shortcut varies depending on your installation).

We should expect that more than just the status code is correct. Let's verify that the body is a list, where every element is an object that contains an id and name. Update your test:

```dart
test("GET /heroes returns 200 OK", () async {
  final response = await harness.agent.get("/heroes");
  expectResponse(response, 200, body: everyElement({
    "id": greaterThan(0),
    "name": isString,
  }));
});
```

This expectation ensures that the body is a list and that every element is an object with a `id` greater than 0, and a `name` that is a string. When expecting a body value, the body is first decoded from its content-type before the expectation. In practice, this means that your JSON response body is deserialized into an object or list. Your expectations of the body are built from Dart objects like `List` and `Object` that deserialized from JSON.

!!! tip "Matchers"
    The function `everyElement` is a `Matcher` from `package:matcher`. There are many types of matchers for all kinds of scenarios, and `package:aqueduct_test` includes Aqueduct-specific matchers. See the [aqueduct_test API Reference](https://www.dartdocs.org/documentation/aqueduct_test/latest/) for all Aqueduct matchers.

This test actually has an error that we will fix in it by using another matcher. Right now, this endpoint returns an *empty list* because there are no heroes in the database! Let's insert a hero before we make this request, and also expect that there is at least one element in the body. Make sure to import `hero.dart` at the top of the file!

```dart
import 'package:heroes/model/hero.dart';

import 'harness/app.dart';

void main() {
  final harness = Harness()..install();

  test("GET /heroes returns 200 OK", () async {
    final query = Query<Hero>(harness.application.channel.context)
      ..values.name = "Bob";

    await query.insert();

    final response = await harness.agent.get("/heroes");
    expectResponse(response, 200,
        body: allOf([
          hasLength(greaterThan(0)),
          everyElement({
            "id": greaterThan(0),
            "name": isString,
          })
        ]));
  });
}
```

This test first inserts a hero named 'Bob' before getting all heroes. We compose a matcher where each element has to match the expected list, but also have a length greater than 0. Re-run your tests, and they should still pass.

## Writing More Tests

Let's write a few more tests for when we `POST /heroes`. In the first test, we'll make a mistake on purpose to see how tests fail. Add the following test:

```dart
test("POST /heroes returns 200 OK", () async {
  final response = await harness.agent.post("/heroes", body: {
    "name": "Fred"
  });
  expectResponse(response, 200, body: {
    "id": greaterThan(0),
    "name": "Bob"
  });
});
```

This test creates a hero named 'Fred', but expects that the returned hero has the name 'Bob'. When we run the test, we see this test failure:

```
Expected: --- HTTP Response ---
          - Status code must be 200
          - Headers can be anything
          - Body after decoding must be:

            {'id': <a value greater than <0>>, 'name': 'Bob'}
          ---------------------
  Actual: TestResponse:<-----------
          - Status code is 200
          - Headers are the following:
            - content-encoding: gzip
            - content-length: 42
            - x-frame-options: SAMEORIGIN
            - content-type: application/json; charset=utf-8
            - x-xss-protection: 1; mode=block
            - x-content-type-options: nosniff
            - server: aqueduct/1
          Decoded body is:
          {id: 1, name: Fred}
          -------------------------
          >
   Which: the body differs for the following reasons:
          was 'Fred' instead of 'Bob' at location ['name']
```

The 'Expected' value tells us the response we expected - that it has a status code of 200, any headers and the body must have a certain structure. The 'Actual' value tells us what the actual response was - a 200 OK, a bunch of headers, and a body a hero named 'Fred'. 'Which' tells us exactly what went wrong - we were expected 'Bob', not 'Fred'. Let's update our test to expect 'Fred'.

```dart
test("POST /heroes returns 200 OK", () async {
  final response = await harness.agent.post("/heroes", body: {
    "name": "Fred"
  });
  expectResponse(response, 200, body: {
    "id": greaterThan(0),
    "name": "Fred"
  });
});
```

We shouldn't just test success cases. Let's also expect that if we try and insert a hero with the same name, we get a 409 error response.

```dart
test("POST /heroes returns 200 OK", () async {
  await harness.agent.post("/heroes", body: {
    "name": "Fred"
  });

  final badResponse = await harness.agent.post("/heroes", body: {
    "name": "Fred"
  });
  expectResponse(badResponse, 409);
});
```

In this test, we request two 'Fred' heroes be created, and the second request fails with a 409 because `name` is a unique property of a hero. Notice that the first request didn't fail, even though we had created a 'Fred' hero in the previous test - that's because we reset the database for each test in our harness.
