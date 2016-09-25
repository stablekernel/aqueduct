---
layout: page
title: "5. Deploying and Other Fun Things"
category: tut
date: 2016-06-23 13:27:59
order: 5
---

This chapter expands on the [previous](http://stablekernel.github.io/aqueduct/tut/model-relationships-and-joins.html).

We've only touched on a small part of Aqueduct, but we've hit the fundamentals pretty well. The rest of the documentation should lead you towards more specific features, in a less hand-holding way. A lot of the code you have written throughout the tutorial is stuff that exists in the [wildfire](https://github.com/stablekernel/wildfire) template-generating package. So it's likely that this is the last time you'll write the 'setup code' you wrote throughout this tutorial.

Make sure you use and check out the instructions on the `wildfire` page when you start building your next project - it has helpful tools for everything we will discuss, takes care of boilerplate, and adds a helper for setting up tests in one line of code.

There is one last thing we want to cover, though, and that is deployment.

We're not going to advocate a specific tool or process for deployment, but we can show you how Aqueduct helps. First, we need to get `quiz`'s schema onto a real database. The following Dart script, available in `wildfire`, will generate a list of PostgreSQL commands to create the appropriate tables, indices and constraints on a PostgreSQL database. You can drop this in your `bin` directory and name it `generate_schema.dart`:

```dart
import 'package:quiz/quiz.dart';
import 'dart:io';

main() {
  var dataModel = new DataModel([Question, Answer]);
  var persistentStore = new PostgreSQLPersistentStore(() => null);
  var ctx = new ModelContext(dataModel, persistentStore);

  var generator = new SchemaGenerator(ctx.dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json);

  var schemaFile = new File("schema.sql");
  schemaFile.writeAsStringSync(pGenerator.commandList);
}
```

Running that script from the top-level directory of `quiz` like this:

```
dart bin/generate_schema.dart
```

will create a file named `schema.sql`. You can add that to a database via the command-line tool for PostgreSQL:

```
psql -h <DatabaseHost> -p <Port> -U <Username> -d <DatabaseName> -f schema.sql
```

(We're currently working on database migration tools, so if you are already thinking about 'OK, but what if I change this?' We're on it.) Next, we need to allow our `quiz` app to take database connection info from a configuration file. For that, we need the `safe_config` package (also by `stable|kernel`). Add it to `pubspec.yaml`:

```yaml
name: quiz
description: A quiz web server
version: 0.0.1
author: Me

environment:
  sdk: '>=1.0.0 <2.0.0'

dependencies:
  aqueduct: any
  safe_config: any

dev_dependencies:
  test: '>=0.12.0 <0.13.0'
```

Then run `pub get`. The `safe_config` package allows you to create subclasses of `ConfigurationItem` that match keys in a config file to prevent you from naming keys incorrectly and enforcing required configuration parameters. There is a built-in class in `safe_config` specifically for database connections, `DatabaseConnectionConfiguration` that we will use. In `pipeline.dart`, declare a new class at the bottom of the file that represents all of the configuration values you will have in `quiz`:

```dart
class QuizConfiguration extends ConfigurationItem {
  QuizConfiguration(String fileName) : super.fromFile(fileName);

  DatabaseConnectionConfiguration database;
}
```

Next, we will create a 'configuration source file'. This file gets checked into source control and is a template for environment-specific configuration files. On a particular instance, you will duplicate this configuration source file and change its values to the appropriate settings for the environment. In the top-level `quiz` directory, create `config.yaml.src` and add the following:

```yaml
database:
 username: dart
 password: dart
 host: localhost
 port: 5432
 databaseName: dart_test  
```

Now, we need to do two things to make this configuration file become a reality. First, whenever we start the `Application`, we need to pass this configuration information to each pipeline. Then, the pipeline must use this information to tell the persistent store of its `ModelContext` where to connect to. (Right now, we hardcoded it to our local database for testing.)

Let's take care of the pipeline stuff first. Add a new static property in `pipeline.dart` and update the constructor:

```dart
class QuizSink extends RequestSink {

  static String ConfigurationKey = "QuizSink.Configuration";

  QuizSink(Map options) : super(options) {
    var dataModel = new DataModel([Question, Answer]);

    var config = options[ConfigurationKey];

    var db = config.database;
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(db.username, db.password, db.host, db.port, db.databaseName);
    context = new ModelContext(dataModel, persistentStore);
  }

  ...
```

Next, we'll need to read in the configuration file as an instance of `QuizConfiguration` and pass it to the startup options of an application. An application will automatically forward this configuration object on to pipelines in their `options` - which we utilize in the code we just wrote. First, let's do this in our tests. Near the top of main function in `question_controller_test.dart`, add configuration parameters to the `app`.

```dart
void main() {
  var app = new Application<QuizSink>();
  var client = new TestClient(app.configuration.port);

  var config = new QuizConfiguration("config.yaml.src");
  app.configuration.pipelineOptions = {
    QuizSink.ConfigurationKey : config
  };

  setUpAll(() async {
    ...
```

Notice here that we load the configuration values from the configuration *source* file. So, the source file serves two roles: it is the template for real instances of your web server, but it also holds the configuration values for testing. This is by convention, and it works itself out really well. Run your tests again - because the configuration source file has the same database connection parameters as your local test database, your tests will still run and pass.

Now, you'll need to update the the `bin/quiz.dart` script that runs the server to also read in a real configuration file.

```dart
import 'package:quiz/quiz.dart';

void main() {
  var config = new QuizConfiguration("config.yaml");
  var app = new Application<QuizSink>()
    ..configuration.pipelineOptions = {
      QuizSink.ConfigurationKey : config
    };

  app.start();
}
```

To get your code onto a server, we recommend putting it in a GitHub repository, setting up an [access key](https://help.github.com/articles/generating-an-ssh-key/), and then cloning the repository onto your remote machine. Then, copy the configuration source file into a file named `config.yaml` (the one being referenced from `bin/quiz.dart`) with values pointing at your actual database. The database you are running won't have questions or answers, so if you wish to one-time seed the database, the following SQL will work (after creating the tables):

```sql
insert into _question (description) values ('How much wood would a woodchuck chuck?');
insert into _question (description) values ('What is the tallest mountain?');
insert into _answer (description, question_index) values ('Depends on if it can.', 1);
insert into _answer (description, question_index) values ('Mount Everest.', 2);
```

(Of course, there are much better ways of doing that than typing it out yourself, but that's a whole other topic.)

Finally, to run your application, you simply run the following command from the top-level of `quiz`:

```
nohup dart bin/start.dart > /dev/null 2>&1 &
```

If you want to take down the server, you can run the kill command on the process. If you're running this on a server, you can just use the following command:

```
pkill dart
```

However, if you are running it locally, don't use the trailing `&`, that way you can simply cancel the process from your command line with Ctrl-C.

Lastly, remember, you'll have to install Dart on your target machine.

Documentation
---

Aqueduct has a built-in Swagger spec documentation generator feature. Check out the [wildfire](https://github.com/stablekernel/wildfire) repository for the `bin/generate_api_docs.dart` script.


Automated Testing/CI
---

Again, `wildfire` is your best bet here as this already exists in projects created with it. However, if you want to add support for running Aqueduct tests as part of Travis-CI, the following .travis.yml file will do:

```yaml
language: dart
sudo: required
addons:
  postgresql: "9.4"
services:
  - postgresql
before_script:
  - psql -c 'create database dart_test;' -U postgres
  - psql -c 'create user dart with createdb;' -U postgres
  - psql -c "alter user dart with password 'dart';" -U postgres
  - psql -c 'grant all on database dart_test to dart;' -U postgres
  - pub get
script: pub run test -j 1 -r expanded
```    

Logging
---

Aqueduct logs requests, the amount of information depending on the result of the request. These are logged at the 'info' level using the `logger` package. At more granular levels, Aqueduct also logs database queries. `wildfire` templates incorporate the `scribe` package to manage logging to files and the console. See it for more examples.
