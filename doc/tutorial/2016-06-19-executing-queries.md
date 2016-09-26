---
layout: page
title: "3. Interacting with a Database"
category: tut
date: 2016-06-19 21:22:35
order: 3
---

This chapter expands on the [previous](http://stablekernel.github.io/aqueduct/tut/writing-tests.html).

Now that you've seen how to route HTTP requests and respond to them, we'll do something useful with those requests: interact with a database. We will continue to build on the last chapter project, `quiz`, by storing the questions in a database and retrieving them from the database.

Building Models
---

Aqueduct has a built-in ORM (some of which is modeled after the iOS/macOS Core Data framework). Like all ORMs, rows of a database are mapped to objects. In Aqueduct, these instances are of type `Model<T>`. Let's define a model that represents a 'question'. Create a new directory in `lib` named `model`, and then add a new file to it named `question.dart` (thus, `quiz/lib/model/question.dart`).

A model is made up of two classes, its instance type and its persistent type. In your responder methods, you'll work with the instances of the instance type. The persistent type is declared once and used to indicate which properties of the model are actually stored in the database. By convention, but not required, persistent types are the name of the instance type, prefixed with '\_'. In `question.dart`, let's define a persistent type for a question:

```dart
part of quiz;

class _Question {
  @primaryKey int index;

  String description;
}
```

Now, link this file to the rest of your project in `lib/quiz.dart` by adding this part at the end of the file:
```
part 'model/question.dart';
```

A persistent type is a simple Dart class. Each property maps to a column in a database and may be marked with `ColumnAttributes` metadata that defines how the underlying database column is defined. The `@primaryKey` metadata is shorthand for the following:

```dart
@ColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

*All models must have a primary key.* Other interesting flags are `indexed`, `nullable` and `defaultValue`. If a property does not have a `ColumnAttributes`, it is still a persistent property, it's just a normal column and its database type is derived from its Dart type. Supported Dart types are `int`, `double`, `String`, `DateTime` and `bool`.

Once a persistent type has been defined, you must define an instance type. The instance type is a subclass of `Model` and must implement its associated persistent type and also provide it as a type argument to `Model<T>`. At the top of this file, but underneath the part of directive, add the following:

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

In order for an application to work with a database, it needs a `ModelContext`. A `ModelContext` is the facilitator between your code, model objects and a database. It is made up of two components, a `DataModel` (the thing that keeps track of all of your model type) and `PersistentStore` (the thing that talks to the database). These objects are set up in a `RequestSink`. In `quiz_sink.dart`, add the following code to the constructor for `QuizSink` and define a new property:

```dart
class QuizSink extends RequestSink {
  QuizSink(Map<String, dynamic> options) : super(options) {
    var dataModel = new DataModel([Question]);
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    context = new ModelContext(dataModel, persistentStore);
  }

  ModelContext context;

  ...
```

(In the future, we'll allow this information to be passed from a configuration file. But for now, we'll do it manually.)

A `DataModel` is initialized with a list of all instance types in your application. The persistent store is a specific implementation of a persistent store, `PostgreSQLPersistentStore`. It is initialized with information necessary to connect to a database. A `ModelContext` simply contains those two things to tie them together.

(By the way, the interface for `PersistentStore` can be implemented for different flavors of SQL and even non-SQL databases. We just so happen to prefer PostgreSQL, so we've already built that one.)

When a `ModelContext` is created, it becomes the *default context* of your application. When we execute database queries, they default to this default context. If we have multiple databases, we can create more `ModelContext`s and pass them around to make sure we hit the right database. For now, we can ignore this, just know that it exists.

Executing Queries
---

Now that we have a context - which can establish a connection to a database, talk to the database and map rows to model objects - we can execute queries in our `RequestController`s. In `question_controller.dart`, remove the list of static questions and replace the code for `getAllQuestions` (we'll work on `getQuestionAtIndex` soon):

```dart
class QuestionController extends HttpController {
  @httpGet getAllQuestions() async {
    var questionQuery = new Query<Question>();
    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }

...
```

When this responder method is executed, it'll create a new `Query` for `Question` (as indicated by the type parameter). A query has a handful of execution methods on it - `fetch`, `fetchOne`, `insert`, `update`, `updateOne` and `delete`. By executing a `fetch` on a vanilla `Query<Question>`, this will return a list of `Question`s, one for each row in the database's question table. Since `Model` objects - which is what `Question`s are - implement the `Serializable` protocol, we can drop them in as the response body object in `Response` and they will be encoded to JSON.

The only problem? We don't have a database yet.

Configuring a Database
---

As we've mentioned a few times, a key facet to Aqueduct is efficient automated testing. The scheme for testing is to create a 'test' database that all of your Aqueduct projects run against. When you run tests against that database, the tests create *temporary* tables prior to executing. The good news is that the `DataModel` in your application can drive this table creation, so you don't need to do anything special. The tests are run against the current version of the schema, as defined by your code.

Therefore, on any machine you're going to test on, you need a database (so, your local machine and your CI platform) that has been configured to have an Aqueduct development database with a specific user. (So, you'll only need to set this up once.) On macOS, the best way to do this locally is download [Postgres.app](http://postgresapp.com). This has a self-contained instance of Postgres that you start by opening up the application itself. Download this application and run it.

Once it starts running, its icon (an elephant) will appear in your menu bar. Select 'Open psql' from its menu, and a command line prompt will appear, connected to the local database. To set up PostgreSQL once and for all for testing, run the following commands in psql:

```sql
create database dart_test;
create user dart with createdb;
alter user dart with password 'dart';
grant all on database dart_test to dart;
```

OK, great, you're done. (You'll want to add Postgres.app to your Startup Items or at least remember to open it before you start development work. It only runs on localhost, so it doesn't open up connections to the outside world.)

You'll notice in your `RequestSink`, the configuration parameters for the `PostgreSQLPersistentStore` match those that you have just added to your local instance of Postgres, so your application will run against that instance. However, if you were to run your code now, the table backing `Question`s would not exist. When running tests, we need to create a temporary table for `Question`s before the tests start. Go to the `setUpAll` method in `question_controller_test.dart`, and enter the following code after the application is started:

```dart
setUpAll(() async {
  await app.start(runOnMainIsolate: true);

  var ctx = ModelContext.defaultContext;
  var schemaGenerator = new SchemaGenerator(ctx.dataModel);
  var commandGenerator = new PostgreSQLSchemaGenerator(schemaGenerator.serialized, temporary: true);

  for (var cmd in commandGenerator.commands) {
    await ctx.persistentStore.execute(cmd);
  }
});
```

After the application is started, we know that it creates a `ModelContext` in the constructor of `QuizSink`. The default context can be accessed through `ModelContext.defaultContext`. We also know that this context has a `DataModel` containing `Question`. The class `SchemaGenerator` will create a database-agnostic JSON schema file from the `DataModel`. Subclasses of `SchemaGeneratorBackend`, like `PostgreSQLSchemaGenerator`, can take that JSON and create SQL commands that create all of the tables, indices and constraints defined by the JSON schema. Each of those is executed on the context, creating the schema in the database. (Note that the `temporary` flag adds makes all of the tables temporary and therefore they disappear when the database connection in the context's persistent store closes.)

Because the `PostgreSQLPersistentStore`'s connection to the database is also a stream, it, too, must be closed to let the test's main function terminate. In `tearDownAll`, add this code before the app is terminated:

```dart
tearDownAll(() async {
  await ModelContext.defaultContext.persistentStore.close();
  await app.stop();
});

```

Now that we can connect to a database prior to our tests running, we need data in that database. You might expect that the tests will fail, and two of them do - but, surprisingly, one of the tests will currently succeed even though there will be no questions in the database. The test that makes sure `/questions` returns a list of strings ending in `?` will succeed because the `everyElement` matcher will check its inner matcher (`endsWith("?")`) will only fail if the inner matcher fails. Since there are no questions returned, the inner matcher never runs. Here's a good opportunity to improve our tests a bit by adding the expectation that there is at least one question. Update the test in `question_controller_test.dart`:

```dart
test("/questions returns list of questions", () async {
  var response = await client.request("/questions").get();
  expect(response, hasResponse(200, everyElement(endsWith("?"))));
  expect(response.decodedBody, hasLength(greaterThan(0)));
});
```

Ok, good, back to all tests failing - as they should, because there are no `Question`s in the database and the old `getQuestionAtIndex` doesn't yet use a database query. Let's first seed the database with some questions using an insert query at the end of `setUpAll`.

```dart
setUpAll(() async {
  await app.start(runOnMainIsolate: true);
  var generator = new SchemaGenerator(ModelContext.defaultContext.dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: true);

  for (var cmd in pGenerator.commands) {
    await ModelContext.defaultContext.persistentStore.execute(cmd);
  }

  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  for (var question in questions) {
    var insertQuery = new Query<Question>()
      ..values.description = question;
    await insertQuery.insert();
  }
});
```

Now, this is also a lesson in insert queries. `Query` has a property named `values`, which will be an instance of the type argument of the `Query` - in this case, a `Question`. When the `Query` is inserted, all of the values that have been set on `values` property are inserted into the database. (If you don't set a value, it isn't sent in the insert query at all. A `Query` does not send `null` unless you explicitly set a value to `null`.)

In our seeded test database, there will be two questions. If you re-run the tests, the first one should pa... wait, no it fails. The test results says this:

```
Expected:
  Status Code: 200
  Body: every element(a string ending with '?')
  Actual: TestResponse:<
  Status Code: 200
  Headers: transfer-encoding: chunked
       content-encoding: gzip
       x-frame-options: SAMEORIGIN
       content-type: application/json; charset=utf-8
       x-xss-protection: 1; mode=block
       x-content-type-options: nosniff
       server: aqueduct/1
  Body: [{"index":1,"description":"How much wood can a woodchuck chuck?"},{"index":2,"description":"What's the tallest mountain in the world?"}]>
```

When a `hasResponse` matcher fails, it prints out what you expected and what the `TestResponse` actually was. The expectation was that every element is a string ending with '?'. Instead, the bottom of the test result says that the body is actually a list of maps, for which there is a index and a description. This is the list of JSON-encoded `Question` objects, and they are obviously not `String`s like they previously were. Let's update this test to reflect that change:

```dart
test("/questions returns list of questions", () async {
  var response = await client.request("/questions").get();
  expect(response, hasResponse(200, everyElement({
      "index" : greaterThan(0),
      "description" : endsWith("?")
  })));
  expect(response.decodedBody, hasLength(greaterThan(0)));
});
```

Now, the expectation is that every element in the response body is a Map, for which it has an `index` greater than or equal to 0 and and a `description` that ends with `?`. Run these tests again, and that first one will now pass. Notice that a `Model` object is encoded so that each property is a key in the resulting JSON.

Go ahead and update the second test for a single question to match this same map.

```dart
test("/questions/index returns a single question", () async {
  var response = await client.request("/questions/1").get();
  expect(response, hasResponse(200, {
      "index" : greaterThanOrEqualTo(0),
      "description" : endsWith("?")
  }));
});
```

Next, let's update the `getQuestionAtIndex` method to use a query, but apply a predicate (a where clause). We're going to show you the ugly way first, then a better way. In `question_controller.dart`, replace the `getQuestionAtIndex` method.

```dart
@httpGet getQuestionAtIndex(int index) async {
  var questionQuery = new Query<Question>()
    ..predicate = new Predicate("index = @idx", {"idx" : index});
  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

So, this is the ugly way. We set the `predicate` of the `Query`. A `Predicate` is basically the same thing as just writing a where clause, except you don't pass input values directly to the `Predicate` string, but instead provide a map of key-value pairs. Each key corresponds to a substitution variable in the format string, prefixed with an `@` symbol. We use `fetchOne` instead of `fetch`, which limits the result set to one row and returns an instance of the type argument of the `Query`, `Question`, instead of a list. If `fetchOne` doesn't yield any results, it returns `null`.

So, this is nice, but the crappy thing about `Predicate`s is that they are strings, and refactoring tools generally won't catch them, and Strings aren't very safe. We can clean this up using a `Query`'s `matchOn` property. The `matchOn` property allows us to set the predicate by assigning matchers to properties of the object being queried. Update `getQuestionAtIndex`:

```dart
@httpGet getQuestionAtIndex(int index) async {
  var questionQuery = new Query<Question>()
    ..matchOn.index = whereEqualTo(index);    

  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

This will create a query that matches on a `Question` where its `index` is equal to value of the `index` local variable. All matchers for `Query`s begin with the word `where`, and there are plenty of them. Check the Aqueduct API reference to see them all. This will yield the same result as the `Predicate` from before.

Run the tests again, good to go!

That's fetch and insert. Delete works the same way - you specify a `predicate` or `matchOn` values and invoke `delete` on the query. If you want to update database rows, you specify both `values` and a `predicate`/`matchOn`.

The more you know: Query Parameters and HTTP Headers
---
You can specify that a `HTTPController` responder method extract HTTP query parameters and headers and supply them as arguments to the method. We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is passed, we'll filter the questions on whether or not that question contains a substring. In `question_controller.dart`, update this method:

```dart
@httpGet getAllQuestions({@HTTPQuery("contains") String contains: null}) async {
  var questionQuery = new Query<Question>();
  if (contains != null) {
    questionQuery.matchOn.description = whereContains(contains);
  }
  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

Notice that the string used to match the query parameter is the first argument to `HTTPQuery`. You may name the associated variable whatever you like, it doesn't have to match the name in the query parameter. Also, note that we first check `contains` to make sure it is not-null. If we simply assigned `null` to `description`, we'd be creating a predicate that checked to see if the `description` *contained* `null`.

Using HTTP header values as parameters is accomplished in the same way, except using the `HTTPHeader` metadata. Both are evaluated case-insensitively.

Then, add a new test:

```dart
test("/questions returns list of questions filtered by contains", () async {
  var response = await client.request("/questions?contains=mountain").get();
  expect(response, hasResponse(200, [{
      "index" : greaterThanOrEqualTo(0),
      "description" : "What's the tallest mountain in the world?"
  }]));
  expect(response.decodedBody, hasLength(1));
});
```

This test will pass, along with the rest of them. It's important to note that GET `/questions` without a `contains` query still yields the correct results. That is because the `HTTPQuery` argument was declared in the optional parameters portion of the responder method. If the parameter were in the required, positional set of parameters and the query string was not included, this request would respond with a 400. (The same positional vs. optional behavior is true of `HTTPHeader`s as well.) For example, if we wanted to make a 'X-Client-ID' header that had to be included on this request, we'd do the following:

```dart
@httpGet getAllQuestions(@HTTPHeader("X-Client-ID") int clientID, {@HTTPQuery("contains") String contains: null}) async {
  if (clientID != 12345) {
    return new Response.unauthorized();
  }

  var questionQuery = new Query<Question>();
  if (contains != null) {
    questionQuery.matchOn.description = whereContains(contains);
  }
  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

Note that in this case, the `clientID` will be parsed as an integer before being sent as an argument to `getAllQuestions`. If the value cannot be parsed as an integer or is omitted, a 400 status code will be returned before your responder method gets called.

Specifying query and header parameters in a responder method is a good way to make your code more intentional and avoid boilerplate parsing code. Additionally, Aqueduct is able to generate documentation from method signatures - by specifying these types of parameters, the documentation generator can add that information to the documentation.
