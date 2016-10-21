---
layout: page
title: "5. Deploying and Other Fun Things"
category: tut
date: 2016-06-23 13:27:59
order: 5
---

This chapter expands on the [previous](model-relationships-and-joins.html).

We've only touched on a small part of Aqueduct, but we've hit the fundamentals pretty well. The rest of the documentation should lead you towards more specific features, in a less hand-holding way. A lot of the code you have written throughout the tutorial is part of the templates that ship with Aqueduct. So it's likely that this is the last time you'll write the 'setup code' you wrote throughout this tutorial.

There is one last thing we want to cover, though, and that is deployment. To begin, we need to get `quiz`'s schema into a real database. Aqueduct has tools for this. First, you must install Aqueduct as a global package:

```bash
pub global activate aqueduct
```

Then, in your project's directory, run the following command:

```bash
aqueduct db generate
```

This command will create a migration file at `migrations/00000001_Initial.migration.dart`. The contents of that file will look like this:

```dart
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

class Migration1 extends Migration {
  Future upgrade() async {
    database.createTable(new SchemaTable("_Question", [
      new SchemaColumn("index", ManagedPropertyType.bigInteger, isPrimaryKey: true,
        autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),

      new SchemaColumn("description", ManagedPropertyType.string, isPrimaryKey: false,
        autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
    ]));

    database.createTable(new SchemaTable("_Answer", [
      new SchemaColumn("id", ManagedPropertyType.bigInteger, isPrimaryKey: true,
        autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),

      new SchemaColumn("description", ManagedPropertyType.string, isPrimaryKey: false,
        autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),

      new SchemaColumn.relationship("question", ManagedPropertyType.bigInteger, relatedTableName: "_Question",
        relatedColumnName: "index", rule: ManagedRelationshipDeleteRule.cascade, isNullable: false, isUnique: true),
    ]));

  }

  Future downgrade() async {
  }
  Future seed() async {
  }
}
```

Notice that the `upgrade` method calls `database.createTable` to create the `_Question` and `_Answer` table. (Recall that table names match the persistent type name of a `ManagedObject` subclass.) Each column in the table is listed with the same `ColumnAttributes` values as declared in your code. As you continue to change your schema, you can create subsequent migration files with `aqueduct db generate`.

This command prepares a migration file, but it does not alter a database in anyway. Before we run this migration, we should validate that the schema it creates matches the `ManagedDataModel` in `quiz`. Now, since this migration file was generated, you can safely bet that it is correct. But, you will have to modify migration files in the future if you make a change to your data model that is too ambiguous for the tools to make a decision on. Therefore, there is a tool to validate that, after running every migration file in `migrations/`, the schema matches the data model of an application.

Let's make an intentional error in this migration that causes a conflict between the data model and generated schema. In `migrations/00000001_Initial.migration.dart`, add a new empty table to the end of `upgrade`:

```dart
Future upgrade() async {
  ...

  database.createTable(new SchemaTable("_Empty", []));
}
```

Now, run the validate command:

```bash
aqueduct db validate
```

This command will fail with the following output:

```
Invalid migrations

Validation failed:
	Compared schema does not contain _Empty, but that table exists in receiver schema.
```

The validation tool will tell you exactly which differences caused a mismatch. Go ahead and remove the line of code that added the table `_Empty` and run validate again. This time, you'll get a success message.

Before we apply this migration, we should provide some seed data - some initial questions and answers. Add the following code to the `seed` method in `migrations/00000001_Initial.migration.dart`:

```dart
Future seed() async {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];
  var answersIterator = [
    "Depends on if they can",
    "Mount Everest"
  ].iterator;

  for (var question in questions) {
    var insertedQuestionRows = await store
      .execute("INSERT INTO _question (description) VALUES (@desc) RETURNING index",
        substitutionValues: {
          "desc" : question
        }) as List<List<int>>;

    answersIterator.moveNext();
    await store
      .execute("INSERT INTO _answer (description, question_index) VALUES (@desc, @idx)",
        substitutionValues: {
          "desc" : answersIterator.current,
          "idx" : insertedQuestionRows.first.first
        });
  }
}
```

When this migration is executed, `upgrade` is called first, creating the tables. Then `seed` is called, adding rows to those tables. Now we can move on to executing this migration. Of course, we need a database first. We'll create this database on our local instance, and we'll also create admin and application-level users.

First, open up a connection to your local database from the command line. (If you are using using `Postgres.app`, choose `Open psql` from its menu. Otherwise, execute the `psql` command line tool.) Within `psql`, run the following commands:

```sql
CREATE DATABASE quiz;

CREATE USER quiz_admin;
ALTER USER quiz_admin WITH PASSWORD 'quiz';
GRANT ALL ON DATABASE quiz TO quiz_admin;

CREATE USER quiz_app;
ALTER USER quiz_app WITH PASSWORD 'quiz';
GRANT CONNECT ON DATABASE quiz TO quiz_app;
\c quiz
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO quiz_app;
```

Notice that we created two users, an admin user and a 'app' user. The admin user will have permission to modify the database's schema, so it will run migrations. The app user will be used by the `quiz` application's `PersistentStore` to make queries. This separation is for security reasons: the application shouldn't have the ability to mess with the schema.

We must now give the `quiz_admin` connection info to the migration tool. This tool defaults to finding this information from a file at `migrations/migration.yaml`. Create this file with the following contents:

```yaml
username: quiz_admin
password: quiz
host: localhost
port: 5432
databaseName: quiz
```

Finally, we can run the database migration. From the project directory, run the following command:

```bash
aqueduct db upgrade
```

You'll get a success message that indicates the database is now at version 1. From within `psql`, you can run the command `\dt` while connected to `quiz` and see the tables that now exist:

```
List of relations
Schema |          Name           | Type  |   Owner    
--------+-------------------------+-------+------------
public | _answer                 | table | quiz_admin
public | _aqueduct_version_pgsql | table | quiz_admin
public | _question               | table | quiz_admin
```

Notice that both `_answer` and `_question` exist, but there is also a `_aqueduct_version_pgsql` table that tracks schema versions. This is how the migration tool determines which migration files to run when upgrading. An entry will be created for each upgrade that is executed, so the current table looks like this:

```
versionnumber |       dateofupgrade        
---------------+----------------------------
            1 | 2016-10-18 16:06:20.235521
```

Also, notice that both `_question` and `_answer` have rows in them.

We can now setup the `quiz` application to connect to this database using the less privileged user. We'll create a configuration file for the application to keep track of this information. The database connection information - as well as other information we might care to configure - can be loaded from a configuration file and passed to a `QuizRequestSink` when it starts up. The request sink will use information from the configuration file to configure its `PostgreSQLPersistentStore` connection, instead of hard-coded values.

To make using configuration files simple, we'll add the `safe_config` package (also by `stable|kernel`) to `quiz`. This package is already included in `aqueduct`, so there is no need to add it as a dependency. The `safe_config` package gives you the ability to define classes in your application that read YAML configuration files. Instances of these classes will read the contents of a YAML file, but will also validate the expected key structure of the YAML file. In `quiz_request_sink.dart`, declare a new class at the bottom of the file for reading configuration files specific to `quiz`:

```dart
class QuizConfiguration extends ConfigurationItem {
  QuizConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
}
```

Since we have a lot to do, we'll direct you to [safe_config on pub](https://pub.dartlang.org/packages/safe_config) if you want a better understanding of how it works. The basic gist is that there must be a key named `database` in any YAML file read with `QuizConfiguration`. The properties of `DatabaseConnectionConfiguration` (declared in `safe_config`) indicate that the `database` key must have `host`, `port`, `databaseName` and optionally `username` and `password` keys.

In the project directory, add a new file `config.yaml` with the following contents:

```yaml
database:
  username: quiz_app
  password: quiz
  host: localhost
  port: 5432
  databaseName: quiz
```

Now, we need to do two things to make this configuration file drive the database connection in `quiz`. First, whenever we start the `Application`, we need to pass this configuration information to each `QuizRequestSink`. Then, the request sink must use this information to configure the `PostgreSQLPersistentStore`.

Add a new static property in `quiz_request_sink.dart` and update the constructor:

```dart
class QuizRequestSink extends RequestSink {
  static String ConfigurationKey = "QuizRequestSink.Configuration";

  QuizRequestSink(Map<String, dynamic> options) : super(options) {
    var dataModel = new ManagedDataModel.fromPackageContainingType(QuizRequestSink);

    var config = options[ConfigurationKey];

    var db = config.database;
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(db.username, db.password, db.host, db.port, db.databaseName);
    context = new ManagedContext(dataModel, persistentStore);
  }

  ...
```

Next, we'll need to read in the configuration file when the application starts and make sure it gets to `QuizRequestSink`. In `bin/start.dart`, add the following code to the top of `main`:

```dart
import 'package:quiz/quiz.dart';

void main() {
  var config = new QuizConfiguration("config.yaml");
  var app = new Application<QuizRequestSink>()
    ..configuration.configurationOptions = {
      QuizRequestSink.ConfigurationKey : config
    };

  app.start();
}
```

Now, when `QuizRequestSink`'s constructor is called, an instance of `QuizConfiguration` with values from `config.yaml` will be available in `options`. We can now run this application. From the command line, run the following:

```bash
dart bin/start.dart
```

Load up http://localhost:8080/questions and http://localhost:8080/question/1 to see the application in action.

However, there is a small problem. The database connection information comes from `config.yaml` when running the application through `start.dart`, but what about when running tests? Right now, the no configuration file is read, and it also doesn't make sense to use the same database for testing as for running. Likewise, you don't want to check in files with sensitive information to source control. Also, as your application evolves, you'll add more keys to the configuration file. It makes sense to have a configuration file for both tests and running instances, and they should both stay in sync in terms of the keys they have.

For this, we recommend creating (and checking in) a `config.yaml.src` file. The configuration source file contains test values for all of the keys your application expects. The tests run off of this configuration file, which in turn ensures that you are testing your configuration file key structure. When you get to a remote instance, you can simply copy the source file to `config.yaml` and you have a template for the configuration file to avoid error.

Create a file in the project directory named `config.yaml.src` and enter the following:

```yaml
database:
  username: dart
  password: dart
  host: localhost
  port: 5432
  databaseName: dart_test
```

Notice that these values are the 'test' database connection values. Your tests will still continue to run against temporary tables in this test database. Now, let's setup our tests to use this configuration file. In `question_controller_test.dart`, update the code near the top of `main`:

```dart
void main() {
  var config = new QuizConfiguration("config.yaml.src");
  var app = new Application<QuizRequestSink>()
    ..configuration.configurationOptions = {
      QuizRequestSink.ConfigurationKey : config
    };

  var client = new TestClient(app);

```

Run your tests and they should all pass.

Deploying Remotely
---

Remote deploys will depend on where an application is deployed to. For services such as EC2 where you have ssh access to the box, we recommend using the script in the templates created by Aqueduct. This script will update from a git repository, fetch dependencies, and run your application detached from the shell. To create a project from an Aqueduct template, you can run the following:

```bash
aqueduct create -n my_project
```

Aqueduct needs to be installed globally for this utility to be available (`pub global activate aqueduct`).

The contents of the `README.md` in the generated project will contain instructions.

To get your code onto a server, we recommend putting it in a GitHub repository, setting up an [access key](https://help.github.com/articles/generating-an-ssh-key/), and then cloning the repository onto your remote machine.

Documentation
---

If you use a template to create a project, you can also generate an OpenAPI specification of your application. The contents of the `README.md` in a Aqueduct generated project will contain instructions on how to perform this task.

Automated Testing/CI
---

If you use a template to create a project, a `.travis.yml` file is created that can be used to run your tests from Travis-CI.

Logging
---

Aqueduct has behavior for logging HTTP requests. For simple console logging, you can simply add the following to the constructor for a `RequestSink` subclass:

```dart
logger.onRecord.listen((rec) => print("$rec"));
```

For more advanced logging, use the `scribe` package (also by `stable|kernel`). This package sets up an isolate specifically for logging that can have multiple logging backends. There are built-in logging backends for writing to a rotating file log or to stdout.

## Creating an Application

Once you are familiar with the fundamentals of the framework, you can get started fast on a new project using templates.

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Run first time setup.

        aqueduct setup

4. Create a new project.

        aqueduct create -n my_project
