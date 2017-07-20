# Executing Queries

We will continue to build on the last chapter's project, `quiz`, by storing questions in a database and retrieving them from the database.

## Object-Relational Mapping

For a quick prelude, let's make sure we understand what an object-relational mapping (ORM) is. There are different kinds of databases that have different use cases. A relational database management system - which pretty much means a 'SQL' database - stores its data in the form of tables. A table represents some sort of entity - like a person or a bank account - and has columns that describe the attributes of that entity - like a name or a balance. Every row in a table is an instance of that entity - like a single person named Bob or Bob's bank account.

In an object-oriented framework like Aqueduct, we have a similar concept: a class represents some sort of entity, and an object with that class is an instance of that entity. An ORM maps rows in a database to and from objects in an application. In Aqueduct, each database table-class pairing is called an *entity*. Collectively, an application's entities are called its data model.

Building a Data Model
---

In our `quiz` application, we really have one type of entity - a "question". We will create an entity by declaring a class whose instances represent a question.

Create a new directory `lib/model/` and then add a new file to it named `lib/model/question.dart`. Add the following code:

```dart
import '../quiz.dart';

class Question extends ManagedObject<_Question> implements _Question {}

class _Question {
  @managedPrimaryKey
  int index;

  String description;
}
```

This declares a "question" entity. The class `_Question` is a one-to-one mapping to a database table with the same name. Each of its properties - `index` and `description` - are columns in that table. When the ORM fetches rows from the `_Question` table, they will be returned as instances of `Question`.

![ManagedObject Diagram](../img/tut3_db.png)

When declaring an entity, there must be two classes:

- A *persistent type* that starts with a `_`, has exactly one primary key property, and declares a property for each database column. In the above, the persistent type is `_Question`.
- An *instance type* that extends `ManagedObject<T>` (where `T` is the persistent type). The instance type also implements the persistent type so that it has the same properties. In the above, the instance type is `Question`.

!!! tip "Why two classes?"
    The two classes allow for much of the powerful behavior of the Aqueduct ORM. Answering this question requires a understanding of those behaviors, which we won't cover much in this beginner's tutorial. Once you've got the basics down, check out [this guide](../db/modeling_data.md) for more detail.

During application initialization, the data model gets compiled so that it information about these entities is available at runtime to the components that need it. In `quiz_sink.dart`, add the following code to the constructor:

```dart
QuizSink(ApplicationConfiguration appConfig) : super(appConfig) {
  /* This line was added by the template */
  logger.onRecord.listen((rec) =>
    print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

  var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
}
```

The `fromCurrentMirrorSystem` constructor will be able to find all of the `ManagedObject<T>` subclasses in your application. This data model will be one of the two necessary components for our next task, creating a `ManagedContext`.

Defining a Context
---

A `ManagedContext` is an application's gateway to a database. It maintains a connection to a database, executes queries on that database, and translates the results to and from `ManagedObject<T>`s according to a `ManagedDataModel`. We have the data model already, so now we must provide database connection information. In `quiz_sink.dart`, declare a new property and add a few more lines to the constructor:

```dart
class QuizSink extends RequestSink {
  QuizSink(ApplicationConfiguration options) : super(options) {
    logger.onRecord.listen((rec) =>
      print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();

    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
      "dart", "dart", "localhost", 5432, "dart_test");

    context = new ManagedContext(dataModel, persistentStore);
  }

  ManagedContext context;

  ...
```

This creates a context that connects to the database `postgres://dart:dart@localhost:5432/dart_test` that has a single `_Question` table. Before we create that database, let's finish writing the code that will fetch questions from a database.

Executing Queries
---

Once a context has been created, when can execute `Query<T>`s on it. In `lib/controller/question_controller.dart`, replace the implementation of `getAllQuestions` to fetch questions from a database and import the file that declares `Question`:

```dart
import '../quiz.dart';
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

In `getAllQuestions`, we create an instance of `Query<Question>` and then execute its `fetch()` method. This method will fetch every question from the database and returns them as a `List<Question>` into the variable `databaseQuestions`. This list is the body object to the `Response`, which by default, encodes them as a list of JSON objects.

!!! note "Where's the context?"
    Most applications only talk to a single database and therefore have a single `ManagedContext`. When creating a `Query<T>` without specifying a context, the query defaults to executing on the last context created - which happens to be the one we instantiated in `QuizSink`.

Now, let's update `getQuestionAtIndex` to fetch a single question by its index from the database.

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

This query does two interesting things: it filters the result of the query by the question's index and only fetches a single question with `fetchOne()`.

Filtering is accomplished through the `where` property of a `Query<Question>`; this property has all of the same properties as `Question`. *Matchers* like `whereEqualTo` are set as the values of `where`'s properties. This adds conditions to the where clause of the generated SQL query. In the above code, we constrain the query to only fetch questions whose `index` is equal to the `index` from the path variable. Since `index` is the primary key of `Question`, this will either give us a single question or return null.

!!! tip "Matching All the Things"
    There are a lot of matchers available to build different queries. All matchers start with the word `where` and can be found by searching the [API reference](https://www.dartdocs.org/documentation/aqueduct/latest/).

Setting Up a Database
---

Ensure that your PostgreSQL installation is running and open the command-line tool `psql`. In this tool, create a new database and a user that can connect to it with the following SQL:

```sql
CREATE DATABASE dart_test;
CREATE USER dart WITH createdb;
ALTER USER dart WITH password 'dart';
GRANT all ON database dart_test TO dart;
```

The user, password and database name match those provided when creating our `ManagedContext` in `QuizSink`. This database will be used during testing. Before the tests run, the test harness will create tables for all of your entities in this database. After the tests complete, the tables will be deleted from this database. Therefore, this database should only be used for running tests.

We must update our test harness to create these tables. In `test/harness/app.dart`, add the following method to `TestApplication`:

```dart
static Future createDatabaseSchema(ManagedContext context) async {
  var builder = new SchemaBuilder.toSchema(
      context.persistentStore, new Schema.fromDataModel(context.dataModel),
      isTemporary: true);

  for (var cmd in builder.commands) {
    await context.persistentStore.execute(cmd);
  }
}
```

Then, in `TestApplication.start`, add the line that calls this method after `await application.start()`:

```dart
Future start() async {
  RequestController.letUncaughtExceptionsEscape = true;
  application = new Application<QuizSink>();
  application.configuration.port = 0;
  application.configuration.configurationFilePath = "config.src.yaml";

  await application.start(runOnMainIsolate: true);

  /* Add this line */
  await createDatabaseSchema(sink.context);

  client = new TestClient(application);
}
```

Now when our tests in `question_controller_test.dart` go through their setup process, the SQL command to create the question table will be executed. The last thing left to do is populate this test database with questions during the test setup process. At the top of `question_controller_test.dart`, import `question.dart`:

```dart
import 'package:quiz/model/question.dart';
```

And then update the `setUpAll` method:

```dart
setUpAll(() async {
  await app.start();

  var questions = [
    new Question()
      ..description = "How much wood can a woodchuck chuck?",
    new Question()
      ..description = "What's the tallest mountain in the world?",
  ];

  await Future.forEach(questions, (q) {
    var query = new Query<Question>()
        ..values = q;
    return query.insert();
  });
});
```

This inserts the two original questions as instances of `Question` into the database during setup. If we were to run our tests now, they would fail and the output would look like this:

```
Expected: --- HTTP Response ---
          - Status code must be 200
          - Headers can be anything
          - Body after decoding must be:

            (an object with length of a value greater than <0> and every element(a string ending with '?'))
          ---------------------
Actual: TestResponse:<-----------
        - Status code is 200
        - Headers are the following:
          - content-encoding: gzip
          - content-length: 124
          - x-frame-options: SAMEORIGIN
          - content-type: application/json; charset=utf-8
          - x-xss-protection: 1; mode=block
          - x-content-type-options: nosniff
          - server: aqueduct/1
        -------------------------
        >
 Which: the body differs for the following reasons:
        has value
        {'index': 1, 'description': 'How much wood can a woodchuck chuck?'}
          which
        {'index': 1, 'description': 'How much wood can a woodchuck chuck?'}
          not a string at index 0
```

Our tests currently verify that the response body contains a list of JSON strings that all end in `?`. However, now that we are returning a list of JSON objects that represent a question, each question has the following form:

```json
{
  "index": 1,
  "description": "How much wood can a woodchuck chuck?"
}
```

We'll need to update our tests so that we're verifying that the *description* of a question object ends with `?`. Wrap the `endsWith("?")` matchers in the two tests that use them with `containsPair`.

```dart
test("/questions returns list of questions", () async {
  expectResponse(
    await app.client.request("/questions").get(),
    200,
    body: allOf([
      hasLength(greaterThan(0)),
      everyElement(containsPair("description", endsWith("?")))
    ]));
});

test("/questions/index returns a single question", () async {
  expectResponse(
    await app.client.request("/questions/1").get(),
    200,
    body: containsPair("description", endsWith("?")));
});
```

Run the tests again by right-clicking on the `main` function and selecting `Run`. They should all pass.

The more you know: Query Parameters and HTTP Headers
---

So far, we have bound HTTP method and path parameters to responder methods in `QuestionController`. You can also bind query parameters, headers and request bodies, too.

We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is part of the request, we'll filter the questions on whether or not that question contains some substring. In `question_controller.dart`, update this method by adding an optional parameter named `containsSubstring`:

```dart
@httpGet
Future<Response> getAllQuestions({@HTTPQuery("contains") String containsSubstring}) async {
  var questionQuery = new Query<Question>();
  if (containsSubstring != null) {
    questionQuery.where.description = whereContainsString(containsSubstring);
  }
  var databaseQuestions = await questionQuery.fetch();
  return new Response.ok(databaseQuestions);
}
```

If an HTTP request has a `contains` query parameter, that value will be available in the `containsSubstring` variable when this method is invoked. Also, note that we first check `containsSubstring` to make sure it is not-null. If we simply assigned `null` to `description`, we'd be creating a matcher that checked to see if the `description` *contained* `null`.

!!! tip "HTTPController Binding"
    For more information on binding, see [this guide](../http/http_controller.md).

Then, add a new test in `question_controller_test.dart`:

```dart
test("/questions returns list of questions filtered by contains", () async {
  var request = app.client.request("/questions?contains=mountain");
  expectResponse(
    await request.get(),
    200,
    body: [{
      "index" : greaterThanOrEqualTo(0),
      "description" : "What's the tallest mountain in the world?"
    }]);  
});
```

This test expects that the body is a list of exactly one object whose description is the one question we know has the word 'mountain' in it.

This test will pass, along with the rest of them. It's important to note that GET `/questions` without a `contains` query still yields the correct results. That is because the `HTTPQuery` argument was declared in the optional parameters portion of the responder method. If the parameter were in the required, positional set of parameters and the query string was not included, this request would respond with a 400. (The same positional vs. optional behavior is true of `HTTPHeader`s as well.)

Binding query and header parameters in a responder method is a good way to make your code more intentional and avoid boilerplate parsing code. Additionally, Aqueduct is able to generate documentation from method signatures - by using bindings, the documentation generator can add that information to the documentation.

## [Next: Relationships and Joins](model-relationships-and-joins.md)
