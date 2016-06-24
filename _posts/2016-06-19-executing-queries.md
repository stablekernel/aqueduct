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

*All models must have a primary key.* Other interesting flags are `indexed`, `nullable` and `defaultValue`. If a property does not have an `Attribute`, it is still a persistent property, it's just a normal column. Supported Dart types are `int`, `double`, `String`, `DateTime` and `bool`.

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

  var generator = new SchemaGenerator(ModelContext.defaultContext.dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: true);

  for (var cmd in pGenerator.commands) {
    await ModelContext.defaultContext.persistentStore.execute(cmd);
  }
});
```

After the application is started, we know that it creates and sets the `ModelContext.defaultContext` with a `DataModel` containing `Question`. The class `SchemaGenerator` will create a database-agnostic JSON schema file. Subclasses of `SchemaGeneratorBackend`, like `PostgreSQLSchemaGenerator`, can take that JSON and create SQL commands that create all of the tables, indices and constraints defined by the JSON schema. Each of those is executed on the context, creating the schema in the database. (Note that the `temporary` flag adds makes all of the tables temporary and therefore they disappear when the database connection in the context's persistent store closes.)

Because the `PostgreSQLPersistentStore`'s connection to the database is also a stream, it, too, must be closed to let the test's main function terminate. In `tearDownAll`, add this code before the app is terminated:

```dart
tearDownAll(() async {
  await ModelContext.defaultContext.persistentStore.close();
  await app.stop();
});

```

Now, if you run your tests, two of them will fail and one of them really should fail, but doesn't. The first test, that checks that every string returned from the `/questions` endpoint should end in a `?` succeeds, but that's because the `everyElement` matcher matches every element, and there are no elements, so it doesn't match any. We never really checked how many questions there were. So, it wasn't a very good test. We don't want to specifically say there are just two questions, so we ought to update that test to make sure there is at least one question. We can apply another expectation, just to the body this time. Update that test in `question_controller_test.dart`:

```dart
test("/questions returns list of questions", () async {
  var response = await client.request("/questions").get();
  expect(response, hasResponse(200, everyElement(endsWith("?"))));
  expect(response.decodedBody, hasLength(greaterThan(0)));
});
```

You can access the String body of a `TestResponse` directly with `body`, its decoded body - like we did here - with `decodedBody`. Or, have the analyzer cast the `decodedBody` into a `List` or `Map` with `asList` or `asMap`. It's sometimes helpful to print out these values during testing, although using `hasResponse` will print out the `TestResponse` on failure.

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

Now, this is also a lesson in insert queries. `Query` has a property named `values`, which will be an instance of the type argument of the `Query` - in this case, a `Question`. It's automatically created the first time you access it, so you can simply start setting properties of a `Question` on it. When the `Query` is inserted, all of the values that have been set on `values` property are inserted into the database. (If you don't set a value, it isn't sent in the insert query at all. It does not send `null` unless you explicitly set a value to `null`.)

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

When a `hasResponse` matcher fails, it prints out what you expected and what the `TestResponse` actually was. The expectation was that every element is a string ending with '?'. Instead, the bottom of the test result says that the body is actually a list of maps, for which there is a index and a description. This is the list of JSON-encoded `Question` objects, and they are obviously not Strings. Let's update this test to test each JSON object in the list.

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

Go ahead and update the second test for a single question to match this same map:

```dart
test("/questions/index returns a single question", () async {
  var response = await client.request("/questions/0").get();
  expect(response, hasResponse(200, {
      "index" : greaterThanOrEqualTo(0),
      "description" : endsWith("?")
  }));
});
```

Next, let's update the `getQuestionAtIndex` method to use a query, but apply a predicate (a where clause). We're going to show you the ugly way first, then a pretty way, then a really pretty way. In `question_controller.dart`, replace the `getQuestionAtIndex` method.

```dart
@httpGet getQuestionAtIndex(int index) async {
  var questionQuery = new Query<Question>()
    ..predicate = new Predicate("index = @idx", {"idx" : index + 1});
  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

So, this is the ugly way. We set the `predicate` of the `Query`. A `Predicate` is basically the same thing as just writing a where clause, except you don't pass input values directly to the `Predicate` format string, but instead provide a map of key-value pairs, where each key is prefixed with an `@` symbol in the format string. (We also increment the index by 1, because we were fetching the question out of a 0-based array, and now we're fetching it by a 1-based primary key.) We use `fetchOne` instead of `fetch`, which limits the result set to one row and returns an instance of the type argument of the `Query`, `Question`, instead of a list. If `fetchOne` doesn't yield any results, it returns `null`.

So, this is nice, but the crappy thing about `Predicate`s is that they are strings, and refactoring tools generally won't catch them, and Strings aren't very safe. We can pretty this up somewhat by using a `ModelQuery<T>`. A `ModelQuery` allows us to set the predicate by referencing property names and using matchers, similar to test matchers. (Except they are different.) Update that method to use a `ModelQuery`:

```dart
@httpGet getQuestionAtIndex(int index) async {
  var questionQuery = new ModelQuery<Question>()
    ..["index"] = whereEqualTo(index + 1);    
  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

To reference a specific property of the Model type argument, you use the brackets and the name of the property. The value is a matcher. All matchers for `Query`s begin with the word `where`, and there are plenty of them. Check the `aqueduct` API reference to see them all. This will yield the same result as the `Predicate` from before.

We can still go one step further, and remove all the strings and get the analyzer to make sure we write the correct property names. Back in `model/question.dart`, create a subclass of `ModelQuery`.

```dart
class QuestionQuery extends ModelQuery<Question> implements _Question {}
```

Note that the type argument is `Question` - the instance type - and the implemented interface is `_Question`, the persistent type. This will create a new class named `QuestionQuery` that will have all the same properties of the persistent type. When we set one of the properties of the persistent type on `QuestionQuery`, it automatically looks up the name of that property and invokes the same `["propertyName"]` setter as it would in a non-specific `ModelQuery`. Update the code again in `getQuestionAtIndex`.

```dart
@httpGet getQuestionAtIndex(int index) async {
  var questionQuery = new QuestionQuery()
    ..index = whereEqualTo(index + 1);    
  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

Run the tests again, good to go!

That's fetch an insert. Delete works the same way - you specify a predicate, or use a `ModelQuery` to define the where clause and invoke `delete` on the query. If you want to update database rows, you specify both `values` and a predicate or `ModelQuery` properties. (Unless you want to update all of the rows, then you don't specify a predicate.)

The more you know: Query parameters
---
You can specify that a `HTTPController` handler method extract HTTP query parameters for you and use them in the handler method. We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is passed, we'll filter the questions on whether or not that question contains the value for `contains`. In `question_controller.dart`, update this method:

```dart
@httpGet getAllQuestions({String contains: null}) async {
    var questionQuery = new QuestionQuery();
    if (contains != null) {
      questionQuery.description = whereContains(contains);
    }
    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }
```

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

This will pass, too - along with the rest of them! Don't worry, you don't have to do this - you can grab all query parameters from the `HTTPController`'s `request.innerRequest`. However, doing this makes your code clearer and will help with the automatic documentation generator we'll talk about later.
