---
layout: page
title: "Interacting with a Database"
category: tut
date: 2016-06-19 21:22:35
order: 3
---

This chapter expands on the [previous](http://stablekernel.github.io/aqueduct/tut/writing-tests.html).

Now that you've seen how to route HTTP requests and respond to them, we'll do something useful with those requests: interact with a database. We will continue to build on the last chapter project, `quiz`, by storing the questions (and answers!) in a database and retrieving them from the database.

Building Models
---

`aqueduct` has a built-in ORM (some of which is modeled after the iOS/macOS Core Data framework). Like all ORMs, rows of a database are mapped to objects. In `aqueduct`, these instances are of type `Model<T>`. Let's define a model that represents a 'question'. Create a new directory in `lib` named `model`, and then add a new file to it named `question.dart`.

A model is made up of two classes, its instance type and its persistent type. In your request handling methods, you deal with the instance type. The persistent type is declared once and used to indicate which properties of the model are actually stored in the database. By convention, but not required, persistent types are the name of the instance type, prefixed with '\_'. In `question.dart`, let's define a persistent type for a question:

```dart
part of quiz;

class _Question {
  @primaryKey
  int index;

  String description;
}
```

Now, link this file to the rest of your project in `lib/quiz.dart` by adding this part at the end of the file:
```
part 'model/question.dart';
```

A persistent type is a simple Dart class. Each property maps to a column in a database and may be marked with metadata. The `@primaryKey` metadata is shorthand for the following metadata:

```dart
@Attributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

Other interesting flags are `indexed`, `nullable` and `defaultValue`. If a property does not have an `Attribute`, it is still a persistent property, it's just a normal column. Supported Dart types are `int`, `double`, `String`, `DateTime` and `bool`.

Once a persistent type has been defined, you must define an instance type. At the top of this file, but underneath the part of directive, add the following:

```dart
part of quiz;

class Question extends Model<_Question> implements _Question {}

class _Question {
  @primaryKey
  int index;

  String description;
}
```

Why there is a persistent and instance type we'll dig into later, but it is important. We now have a model named `Question`. We need to set up the application to interact with a database.

Defining a Context
---

In order for an application to work with a database, it needs a `ModelContext`. A `ModelContext` is the facilitator between your code, model objects and a database. It is made up of two components, a `DataModel` (the thing that keeps track of all model types) and `PersistentStore` (the thing that talks to the database). These objects are set up in a pipeline. In `pipeline.dart`, add the following code to the constructor for `QuizPipeline` and define a new property:

```dart
class QuizPipeline extends ApplicationPipeline {
  QuizPipeline(Map options) : super(options) {
    var dataModel = new DataModel([Question]);
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    context = new ModelContext(dataModel, persistentStore);
  }

  ModelContext context;

  ...
```

(In the future, we'll allow this information to be passed from a configuration and make Dart do the work for us. But for now, we'll do it manually.)

A `DataModel` is initialized with a list of all *instance* model types. The persistent store is a specific implementation of a persistent store, `PostgreSQLPersistentStore` - so by the way, we're using PostgreSQL. It is initialized with information necessary to connect to a database. (We'll handle that in a moment.) A `ModelContext` simply contains those two things to tie them together.

(By the way, the interface for `PersistentStore` can be implemented for different flavors of SQL and even non-SQL databases. We just so happen to prefer PostgreSQL, so we've already built that one.)

When a context is instantiated in a pipeline, the static property `ModelContext.defaultContext` is set to that instance. When we execute database queries - coming up here soon - they default to this default context. If we have multiple databases, we can create more `ModelContext`s and pass them around to make sure we hit the right database. For now, we can ignore this, just know that it exists.

Executing Queries
---

Now that we have a context - which can establish a connection to a database, talk to the database and map rows to model objects - we can execute queries in our `RequestHandler`s. In `question_controller.dart`, remove the list of static questions and replace the code for `getAllQuestions` (we'll work on `getQuestionAtIndex` soon):

```dart
class QuestionController extends HttpController {
  @httpGet getAllQuestions() async {
    var questionQuery = new Query<Question>();
    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }

...
```

When this handler method is hit, it'll create a new `Query` for `Question` (as indicated by the type parameter). A query has a handful of execution methods on it - `fetch`, `fetchOne`, `insert`, `update`, `updateOne` and `delete`. By executing a `fetch` on a vanilla `Query<Question>`, this will return a list of `Question`s, one for each row in the database's question table. Since `Model` objects - which is what `Question`s are - implement the `Serializable` protocol, we can drop them in as the response body object in `Response` and they will be encoded to JSON.

The only problem? We don't have a database yet.

Configuring a Database
---

As we've mentioned a few times, a key facet to `aqueduct` is efficient automated testing. The scheme for testing is to create a 'test' database that all of your `aqueduct` projects run against. When you run tests against that database, the tests create *temporary* tables prior to executing. The good news is that the `DataModel` in your application can drive this table creation, so you don't need to do anything special. The tests are run against the current version of the schema, as defined by your code.

Therefore, on any machine you're going to test on, you need a database (so, your local machine and your CI) that has been configured to have an `aqueduct` development database with a specific user. (So, you'll only need to set this up once.) On macOS, the best way to do this locally is download [Postgres.app](http://postgresapp.com). This has a self-contained instance of Postgres that you start by opening up the application itself. Download this application and run it.

Once it starts running, its icon (an elephant) will appear in your menu bar. Select 'Open psql' from its menu, and a command line prompt will appear, connected to the local database. To set up PostgreSQL once and for all for testing, run the following commands in psql:

```sql
create database dart_test;
create user dart with createdb;
alter user dart with password 'dart';
grant all on database dart_test to dart;
```

OK, great, you're done. (You'll want to add Postgres.app to your Startup Items or at least remember to open it before you start development work. It only runs on localhost, so it doesn't open up connections to the outside world.)

You'll notice in your pipeline, the configuration parameters for the `PostgreSQLPersistentStore` match those that you have just added to your local instance of Postgres, so  your application will run against that instance. However, if you were to run your code now, the table backing `Question`s would not exist. If we are running tests, we need to create a temporary table for `Question`s before the tests start. Go to the `setUpAll` method in `question_controller_test.dart`, and enter the following code after the application is started:

```dart
setUpAll(() async {
  await app.start(runOnMainIsolate: true);

  var generator = new SchemaGenerator(ModelContext.defaultContext.persistentStore, ModelContext.defaultContext.dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: true);

  for (var cmd in pGenerator.commands) {
    await ModelContext.defaultContext.persistentStore.execute(cmd);
  }
});
```

After the application is started, we know that it creates and sets the `ModelContext.defaultContext` with a `DataModel` containing `Question`. 
