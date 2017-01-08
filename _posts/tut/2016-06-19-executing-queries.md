---
layout: page
title: "3. Interacting with a Database"
category: tut
date: 2016-06-19 21:22:35
order: 3
---

[Getting Started](getting-started.html) | [Writing Tests](writing-tests.html) | Executing Queries | [ManagedObject Relationships and Joins](model-relationships-and-joins.html) | [Deployment](deploying-and-other-fun-things.html)

Now that you've seen how to route HTTP requests and respond to them, we'll do something useful with those requests: like interacting with a database. We will continue to build on the last chapter project, `quiz`, by storing the questions in a database and retrieving them from the database.

Building Models
---

Aqueduct has a built-in ORM (some of which is modeled after the iOS/macOS Core Data framework). Like all ORMs, rows of a database are mapped to objects. In Aqueduct, these objects are of type `ManagedObject<T>`. Let's define a managed object that represents a 'question'. Create a new directory in `lib` named `model`, and then add a new file to it named `question.dart` (thus, `lib/model/question.dart`).

A managed object is a subclass of `ManagedObject<T>`, where `T` is a *persistent type*. A persistent type is a simple Dart class that maps to a database table. Each of its properties maps to a column in that table. By convention, but not required, persistent types are prefixed with '\_'. In `question.dart`, let's define a persistent type for a question:

```dart
import 'package:quiz/quiz.dart';

class _Question {
  @managedPrimaryKey int index;

  String description;
}
```

Each property in a persistent type can be marked with `ManagedColumnAttributes` metadata that defines how the underlying database column is defined. The `@managedPrimaryKey` metadata is shorthand for the following:

```dart
@ManagedColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
```

*All managed objects must have one property with `primaryKey` set to true.* Other interesting flags for `ManagedColumnAttributes` are `indexed`, `nullable` and `defaultValue`. If a property does not have a `ManagedColumnAttributes`, it is still a persistent property, it's just a normal column and its database type is inferred from its Dart type. Supported Dart types are `int`, `double`, `String`, `DateTime` and `bool`.

Once a persistent type has been defined, you must declare a subclass of `ManagedObject`. At the top of `question.dart`, but underneath the import, add the following:

```dart
import 'package:quiz/quiz.dart';

class Question extends ManagedObject<_Question> implements _Question {}
class _Question {
  @managedPrimaryKey int index;

  String description;
}
```

When writing code that works with `Question`s, we use the `Question` type. The `_Question` persistent type provides the database mapping information, and your code never works with it directly. A managed object has some special behavior that makes working with database rows as objects more palatable. A subclass of `ManagedObject<T>` should always implement its persistent type (`T`) - here, `Question` implements `_Question`. This allows the Dart analyzer to see that `Question` has all of the properties of `_Question`, but the behavior of `ManagedObject<T>` is responsible for providing storage for those properties.

Importing ManagedObjects
---

As your code progresses, those `ManagedObject<T>`s will have relationships with other `ManagedObject<T>`s and be used across many different `RequestController`s. Additionally, the tools that generate database schemas and 'compile' the declarations of `ManagedObject<T>` so that your application can use them also need to see the definitions. Therefore, it is best to declare each `ManagedObject<T>` in its own file, but declare a library file that exports all `ManagedObject<T>`s, which is also exported from your top-level application library file. Every `ManagedObject<T>` should be visible by importing the top-level application library file.

Therefore, create a new file in `lib` named `model.dart`. In this file, export `model/question.dart`:

```dart
export 'model/question.dart';
```

In `quiz.dart`, export `model.dart`:

```dart
export 'model.dart';
```

Now, every file in your application that import the application package will see the managed object declarations - and more importantly, the tools will see those declarations, too.

Defining a Context
---

In order for an application to work with a database, it needs a `ManagedContext`. A `ManagedContext` is the facilitator between your code and a database. It is made up of two components, a `ManagedDataModel` (the thing that keeps track of all of your managed object types) and `PersistentStore` (the thing that talks to the database). These objects are set up in a `RequestSink`. In `quiz_request_sink.dart`, add the following code to the constructor for `QuizRequestSink` and define a new property:

```dart
class QuizRequestSink extends RequestSink {
  QuizRequestSink(Map<String, dynamic> options) : super(options) {
    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
      "dart", "dart", "localhost", 5432, "dart_test");
    context = new ManagedContext(dataModel, persistentStore);
  }

  ManagedContext context;

  ...
```

(In the future, we'll allow this information to be passed from a configuration file. But for now, we'll do it manually.)

A `ManagedDataModel` is initialized with its named constructor `fromCurrentMirrorSystem`. This constructor uses reflection to find every `ManagedObject<T>` subclass in your application and compile a data model from them. (This is why it is important to export managed objects the way it was done in the previous section.)

The persistent store is a specific implementation of a persistent store, `PostgreSQLPersistentStore`. It is initialized with information necessary to connect to a database. A `ManagedContext` simply ties those two things together.

(By the way, the interface for `PersistentStore` can be implemented for different flavors of SQL and even non-SQL databases. We just so happen to prefer PostgreSQL, so we've already built that one.)

When a `ManagedContext` is created, it becomes the *default context* of your application. When we execute database queries, they run on the default context (by default). If we have multiple databases, we can create more `ManagedContext`s and pass them around to make sure we hit the right database. For now, we can ignore this, just know that it exists.

Executing Queries
---

Now that we have a context - which can establish a connection to a database, talk to the database and map rows to managed objects - we can execute queries in our `RequestController`s. In `question_controller.dart`, replace the code for `getAllQuestions` (we'll work on `getQuestionAtIndex` soon):

```dart
class QuestionController extends HttpController {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @httpGet getAllQuestions() async {
    var questionQuery = new Query<Question>();
    var databaseQuestions = await questionQuery.fetch();
    return new Response.ok(databaseQuestions);
  }

...
```

When this responder method is executed, it'll create a new `Query<T>` for `Question` (as indicated by the type parameter). A query has a handful of execution methods on it - `fetch`, `fetchOne`, `insert`, `update`, `updateOne` and `delete`. By executing a `fetch` on a vanilla `Query<Question>`, this will return a list of `Question`s, one for each row in the database's question table. Since `ManagedObject`s - which is what `Question`s are - implement the `Serializable` protocol, we can drop them in as the response body object in `Response` and they will be encoded to JSON.

The only problem? We don't have a database yet.

Configuring a Database
---

As we've mentioned a few times, a key facet to Aqueduct is efficient automated testing. The scheme for testing is to create a 'test' database that all of your Aqueduct projects run against. When you run tests against that database, the tests create *temporary* tables prior to executing. The good news is that the `ManagedDataModel` in your application can drive this table creation, so you don't need to do anything special. The tests are run against the current version of the schema defined by your code.

Therefore, on any machine you're going to test on, you need a database (so, your local machine and your CI platform) that has been configured to have an Aqueduct development database with a specific user. (You'll only need to set this up once.) On macOS, the best way to do this locally is download [Postgres.app](http://postgresapp.com). This has a self-contained instance of Postgres that you start by opening up the application itself. Download this application and run it.

Once running, run the command `aqueduct setup` from anywhere. It will give you some additional instructions to follow to make sure everything is OK. It just runs the following SQL:

```sql
create database dart_test;
create user dart with createdb;
alter user dart with password 'dart';
grant all on database dart_test to dart;
```

OK, great, you're done. (You'll want to add Postgres.app to your Startup Items or at least remember to open it before you start development work. It only runs on localhost, so it doesn't open up connections to the outside world.)

You'll notice in your `RequestSink`, the configuration parameters for the `PostgreSQLPersistentStore` match those that you have just added to your local instance of Postgres, so your application will run against that instance. However, if you were to run your code now, the table backing `Question`s would not exist. When running tests, we need to create a temporary table for `Question`s before the tests start. Go to the `setUp` method in `question_controller_test.dart`, and enter the following code after the application is started:

```dart
  setUp(() async {
    await app.start(runOnMainIsolate: true);

    var ctx = ManagedContext.defaultContext;
    var builder = new SchemaBuilder.toSchema(
      ctx.persistentStore, new Schema.fromDataModel(ctx.dataModel), isTemporary: true);

    for (var cmd in builder.commands) {
      await ctx.persistentStore.execute(cmd);
    }
  });
```

After the application is started, we know that it creates a `ManagedContext` in the constructor of `QuizRequestSink`. The default context can be accessed through `ManagedContext.defaultContext`. We also know that this context has a `ManagedDataModel` containing `Question`. The class `SchemaBuilder` will create a series of SQL commands from the `ManagedDataModel`, translated by the `PostgreSQLPersistentStore`. (Note that the `isTemporary` parameter makes all of the tables temporary and therefore they disappear when the database connection in the context's persistent store closes. This prevents changes to the database from leaking into subsequent tests.)

Because the `PostgreSQLPersistentStore`'s connection to the database is also a stream, it, too, must be closed to let the test's main function terminate. In `tearDownAll`, add this code before the app is terminated:

```dart
  tearDownAll(() async {
    await ManagedContext.defaultContext.persistentStore.close();
    await app.stop();
  });
```

We now need questions in the database (you can run your tests and see the they fail because there are no questions). Let's first seed the database with some questions using an insert query at the end of `setUp`.

```dart
  setUpAll(() async {
    await app.start(runOnMainIsolate: true);
    var ctx = ManagedContext.defaultContext;
    var builder = new SchemaBuilder.toSchema(ctx.persistentStore, new Schema.fromDataModel(ctx.dataModel), isTemporary: true);

    for (var cmd in builder.commands) {
      await ctx.persistentStore.execute(cmd);
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

Now, this is also a lesson in insert queries. `Query<T>` has a property named `values`, which will be an instance of the type argument of the `Query<T>` - in this case, a `Question`. When the `Query<T>` is inserted, all of the values that have been set on `values` property are inserted into the database. (If you don't set a value, it isn't sent in the insert query at all. A `Query<T>` does not send `null` unless you explicitly set a value to `null`.)

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

When a `hasResponse` matcher fails, it prints out what you expected and what the `TestResponse` actually was. The expectation was that every element is a string ending with '?'. Instead, the bottom of the test result says that the body is actually a list of maps, for which there is a index and a description. This is the list of JSON-encoded `Question` objects, and they are obviously not `String`s like they previously were.

A `ManagedObject` is serialized into a `Map<String, dynamic>`, where each key is a property of the managed object. Since `Question` declares two properties - `index` and `description` - each question in the response body JSON is a map of those two values. Let's update this test to reflect that change:

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

Now, the expectation is that every element in the response body is a `Map`, for which it has an `index` greater than or equal to `0` and and a `description` that ends with `?`. Run these tests again, and that first one will now pass.

Go ahead and update the second test for a single question to match this same map. Even though the code to get a question by index does not yet have this update.

```dart
  test("/questions/index returns a single question", () async {
    var response = await client.request("/questions/1").get();
    expect(response, hasResponse(200, {
        "index" : greaterThanOrEqualTo(0),
        "description" : endsWith("?")
    }));
  });
```

This test should now fail, but it tests what we want. Update the `getQuestionAtIndex` method to use a query, but apply a *matcher* to the `Question.index`. In `question_controller.dart`, replace the `getQuestionAtIndex` method.

```dart
  @httpGet getQuestionAtIndex(@HTTPPath("index") int index) async {
    var questionQuery = new Query<Question>()
      ..matchOn.index = whereEqualTo(index);    

    var question = await questionQuery.fetchOne();

    if (question == null) {
      return new Response.notFound();
    }
    return new Response.ok(question);
  }
```

Matchers are constants and functions that get assigned to properties of a query's `matchOn` property. They modify the query to include a `where` clause, which filters the result set. This particular query will create a query that matches on a `Question` whose `index` is equal to value of the `index` local variable. There are many matchers available, and all matchers for `Query<T>`s begin with the word `where`. Check the [Aqueduct API reference](https://www.dartdocs.org/documentation/aqueduct/latest) to see them all.

Run the tests again, good to go! Now go ahead and delete the property `questions` for `QuestionController`, so the final class looks like this:

```dart
class QuestionController extends HTTPController {
  @httpGet getAllQuestions() async {
    var questionQuery = new Query<Question>();
    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }


  @httpGet
  Future<Response> getQuestionAtIndex(@HTTPPath("index") int index) async {
    var questionQuery = new Query<Question>()
      ..matchOn.index = whereEqualTo(index);    

    var question = await questionQuery.fetchOne();

    if (question == null) {
      return new Response.notFound();
    }
    return new Response.ok(question);
  }
}
```

That's fetch and insert. Delete works the same way - you specify `matchOn` values and invoke `delete` on the query. If you want to update database rows, you specify both `values` and `matchOn`.

The more you know: Query Parameters and HTTP Headers
---
You can specify that a `HTTPController` responder method extract HTTP query parameters and headers and supply them as arguments to the method. We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is part of the request, we'll filter the questions on whether or not that question contains some substring. In `question_controller.dart`, update this method:

```dart
  @httpGet getAllQuestions({@HTTPQuery("contains") String containsSubstring: null}) async {
    var questionQuery = new Query<Question>();
    if (containsSubstring != null) {
      questionQuery.matchOn.description = whereContains(containsSubstring);
    }
    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }
```

If an HTTP request has a `contains` query parameter, that value will be passed as the `containsSubstring` parameter. As you can see, you may name the parameter whatever you like, it doesn't have to match the name of query parameter. Also, note that we first check `containsSubstring` to make sure it is not-null. If we simply assigned `null` to `description`, we'd be creating a matcher that checked to see if the `description` *contained* `null`.

Using HTTP header values as parameters is accomplished in the same way, except using the `HTTPHeader` metadata. Query parameters are case sensitive, where header parameters are not.

Then, add a new test in `question_controller_test.dart`:

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
  @httpGet getAllQuestions(
    @HTTPHeader("X-Client-ID") int clientID,
    {@HTTPQuery("contains") String containsSubstring: null}
  ) async {
    if (clientID != 12345) {
      return new Response.unauthorized();
    }

    var questionQuery = new Query<Question>();
    if (containsSubstring != null) {
      questionQuery.matchOn.description = whereContains(containsSubstring);
    }

    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }
```

Note that in this case, the `clientID` will be parsed as an integer before being sent as an argument to `getAllQuestions`. If the value cannot be parsed as an integer or is omitted, a 400 status code will be returned before your responder method gets called.

Specifying query and header parameters in a responder method is a good way to make your code more intentional and avoid boilerplate parsing code. Additionally, Aqueduct is able to generate documentation from method signatures - by specifying these types of parameters, the documentation generator can add that information to the documentation.

## [Next: Relationships and Joins](model-relationships-and-joins.html)
