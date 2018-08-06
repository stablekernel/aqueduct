# 5. Deploying an Aqueduct Application

The last chapter is a quick one - we'll get our application and its database running locally. When writing tests, the harness creates temporary tables that are destroyed when the tests end. Those tables are created in a database named `dart_test` that is exclusively used for this purpose. All of your projects will use this same database for running tests.

To run the application outside of the tests, you'll need another database. Run the `psql` command-line tool and enter the following SQL:

```sql
CREATE DATABASE quiz;
CREATE USER quiz_user WITH createdb;
ALTER USER quiz_user WITH password 'quizzy';
GRANT all ON database quiz TO quiz_user;
```

This creates a database `quiz` that `quiz_user` has access to. Now, add `quiz`'s data model to this database by running the following commands in the project directory:

```
aqueduct db generate
aqueduct db upgrade --connect postgres://quiz_user:quizzy@localhost:5432/quiz
```

The first command generates a migration file in `migrations/` that adds tables `_Question` and `_Answer`, and the second command executes that migration file on the newly created database.


After adding the data model to the `quiz` database, run the following commands in `psql` to insert a question and answer:

```sql
\c quiz
INSERT INTO _question (description) VALUES ('What is 1+1?');
INSERT INTO _answer (description, question_index) VALUES ('2', 1);
```

The application is currently hard-coded to connect to the test database. We'll write a bit of code to read connection info from a YAML configuration file instead. At the bottom of `quiz_sink.dart`, create a `Configuration` subclass:

```dart
class QuizConfig extends Configuration {
  QuizConfig(String filename) : super.fromFile(filename);

  DatabaseConnectionConfiguration database;
}
```

Update `QuizSink`'s constructor to create its persistent store from configuration values:

```dart
QuizSink(ApplicationOptions appConfig) : super(appConfig) {
  logger.onRecord.listen((rec) =>
    print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));
  var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();

  var configValues = new QuizConfig(appConfig.configurationFilePath);

  var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
      configValues.database.username,
      configValues.database.password,
      configValues.database.host,
      configValues.database.port,
      configValues.database.databaseName);
  context = new ManagedContext(dataModel, persistentStore);
}
```

Finally, create the file `config.yaml` in the root of the project directory and add the following key-values pairs:

```
database:
 username: quiz_user
 password: quizzy
 host: localhost
 port: 5432
 databaseName: quiz
```

Run `aqueduct serve` and open a browser to `http://localhost:8888/questions` - you'll see the question in your database. For other ways of running an Aqueduct application (and tips for running them remotely), see [this guide](../deploy/index.md).

!!! tip "Test and Deployment Configuration"
    The `configurationFilePath` defaults to `config.yaml` when using `aqueduct serve`. In the test harness, the `configurationFilePath` is set to `config.src.yaml`. To continue running the tests, add the database connection configuration for `dart_test` database to the file `config.src.yaml`. For more details on configuration, see [this guide](../http/configure.md).

## Onward

We've only touched on a small part of Aqueduct, but we've hit the fundamentals pretty well. The rest of the guides on this site will take you deeper on these topics, and topics we haven't covered like OAuth 2.0.

It's very important that you get comfortable using the [API reference](https://www.dartdocs.org/documentation/aqueduct/latest) in addition to these guides. If you are looking to solve a problem, start by looking at the API reference for all of the objects you have access to (including the type you are writing the method for). The properties and methods you have access to will lead you to more properties and methods that'll eventually do what you want done.

Users of the documentation viewer [Dash](https://kapeli.com/dash) can add Aqueduct through the `Preferences` pane, under `Downloads`.

There are IntelliJ IDEA file and code templates available for Aqueduct. See [this guide](../intellij.md) for installation instructions and usage. It takes 10 seconds and it'll save you a ton of time overall.

And lastly, remember to create a new project:

```
aqueduct create my_next_big_idea
```
