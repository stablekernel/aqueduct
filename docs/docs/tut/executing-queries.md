# Executing Queries

Now that you've seen how to route HTTP requests and respond to them, we'll do something useful with those requests: like interacting with a database. We will continue to build on the last chapter project, `quiz`, by storing the questions in a database and retrieving them from the database.

Building a Data Model
---

Aqueduct has a built-in ORM (some of which is modeled after the iOS/macOS Core Data framework). Like all ORMs, rows of a database are mapped to objects. In Aqueduct, these objects are of type `ManagedObject<T>`. Let's define a managed object that represents a 'question'. Create a new directory in `lib` named `model`, and then add a new file to it named `question.dart` (thus, `lib/model/question.dart`).

A managed object is a subclass of `ManagedObject<T>`, where `T` is a *persistent type*. A persistent type is a simple Dart class that maps to a database table. Each of its properties maps to a column in that table. Persistent types are prefixed with '\_'. In `question.dart`, let's define a persistent type for a question:

```dart
import '../quiz.dart';

class _Question {
  @ManagedColumnAttributes(primaryKey: true, databaseType: PropertyType.bigInteger, autoincrement: true)
  int index;

  String description;
}
```

Each property in a persistent type can be marked with `ManagedColumnAttributes` metadata that defines how the underlying database column is defined. The `index` property of `_Question` is the primary key column and a "big" integer. The autoincrement flag lets the database generate this value when a new question is inserted. Because it is quite common to have a primary key that is a big integer and autoincrementing, there is shorthand for it. Replace the metadata with the `managedPrimaryKey` shorthand:

```dart
class _Question {
  @managedPrimaryKey
  int index;

  String description;
}
```

*All managed objects must have exactly one property with `primaryKey` set to true.* Other interesting flags for `ManagedColumnAttributes` are `indexed`, `nullable` and `defaultValue`. If a property does not have `ManagedColumnAttributes`, it is still a persistent property. All of the , it's just a normal column and its database type is inferred from its Dart type. Supported Dart types are `int`, `double`, `String`, `DateTime` and `bool`.

Once a persistent type has been defined, you must also declare a corresponding subclass of `ManagedObject`. At the top of `question.dart`, but underneath the import, add the following:

```dart
import '../quiz.dart';

class Question extends ManagedObject<_Question> implements _Question {}
class _Question {
  @managedPrimaryKey
  int index;

  String description;
}
```

This dual-class setup is important and necessary for using Aqueduct's ORM. The persistent type - the plain Dart class that starts with an underscore - represents a database table. Each property of the persistent type is a column in that database table. The name of the database table matches the name of the class (here, `_Question`).

The `ManagedObject` subclass is the type you work with in your code. Its associated persistent type appears twice in its declaration: as the type argument to `ManagedObject` (`ManagedObject<_Question>`) and as an interface (`implements _Question`). A `ManagedObject` may have properties and methods of its own, but those are *not* backed by a database column.

Defining a Context
---

In order for an application to work with a database, it needs a `ManagedContext`. A `ManagedContext` is the facilitator between your code and a database. It is made up of two components, a `ManagedDataModel` (the thing that keeps track of all of your managed object types) and `PersistentStore` (the thing that talks to the database). These objects are set up in a `RequestSink`. In `sink.dart`, add the following code to the constructor for `QuizRequestSink` and define a new property:

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

A `ManagedDataModel` is initialized with its named constructor `fromCurrentMirrorSystem`. This constructor uses reflection to find every `ManagedObject<T>` subclass in your application and compile a data model from them.

The persistent store is a specific implementation of a persistent store, `PostgreSQLPersistentStore`. It is initialized with information necessary to connect to a database. A `ManagedContext` simply ties those two things together.

(By the way, the interface for `PersistentStore` can be implemented for different flavors of SQL and even non-SQL databases. We just so happen to prefer PostgreSQL, so we've already built that one.)

When a `ManagedContext` is created, it becomes the *default context* of your application. When we execute database queries, they run on the default context (by default). If we have multiple databases, we can create more `ManagedContext`s and pass them around to make sure we hit the right database. For now, we can ignore this, just know that it exists.

Executing Queries
---

Now that we have a context - which can establish a connection to a database, talk to the database and map rows to managed objects - we can execute queries in our `RequestController`s. In `question_controller.dart`, import `question.dart` and replace the code for `getAllQuestions` (we'll work on `getQuestionAtIndex` soon):

```dart
import '../model/question.dart';

class QuestionController extends HttpController {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @httpGet
  Future<Response> getAllQuestions() async {
    var questionQuery = new Query<Question>();
    var databaseQuestions = await questionQuery.fetch();
    return new Response.ok(databaseQuestions);
  }

...
```

When this responder method is executed, it'll create a new `Query<T>` for `Question` (as indicated by the type parameter). A query has a handful of execution methods on it - `fetch`, `fetchOne`, `insert`, `update`, `updateOne` and `delete`. By executing a `fetch` on a vanilla `Query<Question>`, this will return a list of `Question`s, one for each row in the database's question table.

Now, we need an actual database to fetch data from.

Configuring a Database
---

As we've mentioned a few times, a key facet to Aqueduct is efficient automated testing. The scheme for testing is to create a 'test' database that all of your Aqueduct projects run against. When you run tests against that database, the tests create *temporary* tables prior to executing. The good news is that the `ManagedDataModel` in your application can drive this table creation, so you don't need to do anything special. The tests are run against the current version of the schema defined by your code.

Therefore, on any machine you're going to test on, you need to install PostgreSQL and configure a test database. You'll only need to set this up once on - all Aqueduct project tests run against the same database.

On macOS, the best way to do this with [Postgres.app](http://postgresapp.com). This macOS app has a self-contained instance of Postgres that you start by opening up the application itself. Download this application and run it.

Once running, run the command `aqueduct setup` from anywhere. It will give you some additional instructions to follow to make sure everything is OK. It just runs the following SQL:

```sql
create database dart_test;
create user dart with createdb;
alter user dart with password 'dart';
grant all on database dart_test to dart;
```

If you are on another operating system or this command fails for your installation of PostgreSQL, you may run the above commands through the `psql` command-line utility.

You'll notice in your `RequestSink`, the configuration parameters for the `PostgreSQLPersistentStore` match those that you have just added to your local instance of Postgres, so your application will run against that instance. However, if you were to run your code now, the table backing `Question`s would not exist. When running tests, we need to create a temporary table for `Question`s before the tests start. Go to the `setUp` method in `question_controller_test.dart`, and enter the following code after the application is started:

```dart
  setUp(() async {
    await app.start(runOnMainIsolate: true);
    client = new TestClient(app);

    var ctx = ManagedContext.defaultContext;
    var builder = new SchemaBuilder.toSchema(
      ctx.persistentStore, new Schema.fromDataModel(ctx.dataModel), isTemporary: true);

    for (var cmd in builder.commands) {
      await ctx.persistentStore.execute(cmd);
    }
  });
```

After the application is started, we know that it creates a `ManagedContext` in the constructor of `QuizRequestSink`. The default context can be accessed through `ManagedContext.defaultContext`. We also know that this context has a `ManagedDataModel` containing `Question`. The class `SchemaBuilder` will create a series of SQL commands from the data model, translated by the `PostgreSQLPersistentStore`. (Note that the `isTemporary` parameter makes all of the tables temporary and therefore they disappear when the database connection in the context's persistent store closes. This prevents changes to the database from leaking into subsequent tests.)

The database connection is automatically closed when the tests complete by the existing `tearDown` method that stops the application. Note that when the databsae connection is closed, the tables and data in the database created by this test are discarded.

We now need questions in the database (you can run your tests and see the they fail because there are no questions). Let's first seed the database with some questions using an insert query at the end of `setUp`.

```dart
// Don't forget this import!
import 'package:quiz/model/question.dart';

void main() {
  setUp(() async {
    await app.start(runOnMainIsolate: true);
    client = new TestClient(app);

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

Now, this is also a lesson in insert queries. `Query<T>` has a property named `values`, an instance of the type being queried. In this case, `values` is a `Question` because the query is created as `Query<Question>`. When the `Query<T>` is inserted, all of the values that have been set on `values` property are inserted into the database. (If you don't set a value, it isn't sent in the insert query at all. A `Query<T>` does not send `null` unless you explicitly set a property to `null`.)

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

This is because a `ManagedObject` like `Question` is serialized into a `Map<String, dynamic>` when returned in a `Response`. Each key in the map is a property of the managed object. Since `Question` declares two properties - `index` and `description` - each question in the response body JSON is a map of those two values. Let's update this test to reflect that change:

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

Now, the expectation is that every element in the response body is a `Map`, for which it has an `index` greater than or equal to `0` and and a `description` that ends with `?`. Run these tests again and the tests will pass.

Now, our `QuestionController` reads from a database when fetching all questions through the `/questions` endpoint. However, it is still reading from the list of static questions when fetching a single question with `/questions/:id`.

Modify `getQuestionAtIndex` in `question_controller.dart` to fetch a single question from the database. You may also delete the property `questions` from `QuestionController`.

```dart
  @httpGet
  Future<Response> getQuestionAtIndex(@HTTPPath("index") int index) async {
    var questionQuery = new Query<Question>()
      ..where.index = whereEqualTo(index);    

    var question = await questionQuery.fetchOne();

    if (question == null) {
      return new Response.notFound();
    }
    return new Response.ok(question);
  }
```

In this query, a 'where' is being applied to the query. The `Query.where` property allows you to restrict the results returned from a query to those that match the conditions applied to it. `Query.where` is also an instance of `Question`, like `values`, so its properties like `index` are accessible. When setting a property of `Query.where`, you must use a *matcher*. There are many available matchers and all of them begin with the word 'where'. This particular query only fetches questions where the index is equal to the argument `index`. (Check the [Aqueduct API reference](https://www.dartdocs.org/documentation/aqueduct/latest) to see all of the matchers.)

Now, we must update the second test in `question_controller_test.dart` now that this endpoint is returning a JSON object that represents a question:

```dart
  test("/questions/index returns a single question", () async {
    var response = await client.request("/questions/1").get();
    expect(response, hasResponse(200, {
        "index" : greaterThanOrEqualTo(0),
        "description" : endsWith("?")
    }));
  });
```

That's fetch and insert. Delete works the same way - you specify `where` values and invoke `delete` on the query. If you want to update database rows, you specify both `values` and `where`.

The more you know: Query Parameters and HTTP Headers
---
You can specify that a `HTTPController` responder method extract HTTP query parameters and headers and supply them as arguments to the method. We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is part of the request, we'll filter the questions on whether or not that question contains some substring. In `question_controller.dart`, update this method:

```dart
  @httpGet
  Future<Response> getAllQuestions({@HTTPQuery("contains") String containsSubstring: null}) async {
    var questionQuery = new Query<Question>();
    if (containsSubstring != null) {
      questionQuery.where.description = whereContainsString(containsSubstring);
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
  @httpGet
  Future<Response> getAllQuestions(
    @HTTPHeader("X-Client-ID") int clientID,
    {@HTTPQuery("contains") String containsSubstring = null}
  ) async {
    if (clientID != 12345) {
      return new Response.unauthorized();
    }

    var questionQuery = new Query<Question>();
    if (containsSubstring != null) {
      questionQuery.where.description = whereContainsString(containsSubstring);
    }

    var questions = await questionQuery.fetch();
    return new Response.ok(questions);
  }
```

Note that in this case, the `clientID` will be parsed as an integer before being sent as an argument to `getAllQuestions`. If the value cannot be parsed as an integer or is omitted, a 400 status code will be returned before your responder method gets called.

Specifying query and header parameters in a responder method is a good way to make your code more intentional and avoid boilerplate parsing code. Additionally, Aqueduct is able to generate documentation from method signatures - by specifying these types of parameters, the documentation generator can add that information to the documentation.

## [Next: Relationships and Joins](model-relationships-and-joins.md)
