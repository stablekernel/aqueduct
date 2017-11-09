# 2. Executing Queries

We will continue to build on the last chapter's project, `quiz`, by fetching questions from a database instead of a constant list in code.

## Object-Relational Mapping

A relational database management system (like PostgreSQL or MySQL) stores its data in the form of tables. A table represents some sort of entity - like a person or a bank account. Each table has columns that describe the attributes of that entity - like a name or a balance. Every row in a table is an instance of that entity - like a single person named Bob or a bank account.

In an object-oriented framework like Aqueduct, we have representations for tables, columns and rows. A class represents a table, an instance of that class is a row in the table and each property of an instance is a column. An ORM translates rows in a database to and from objects in an application.

| Aqueduct | Database | Example #1 | Example #2 |
|-|-|-|-|
|Class|Table|Person|Bank Account|
|Property|Column|Person's Name|Bank Account Balance|
|Instance|Row|A person named Bob|Sally's Bank Account|

In Aqueduct, each database table-class pairing is called an *entity*. Collectively, an application's entities are called its *data model*.

Building a Data Model
---

In our `quiz` application, we have one type of entity - a "question". To create a new entity, we must create a subclass of `ManagedObject<T>`. Create a new directory `lib/model/` and then add a new file to this directory named `question.dart`. Add the following code:

```dart
import '../quiz.dart';

class Question extends ManagedObject<_Question> implements _Question {}

class _Question {
  @primaryKey
  int index;

  String description;
}
```

This declares a `Question` entity. Entities are always made up of two classes.

The `_Question` class is a one-to-one representation of a database table. This table's name will have the same name, `_Question`. Every property declared in this class will have a corresponding column in this table. In other words, the `_Question` table will have two columns - `index` and `description`. The `index` column is this table's primary key (a unique identifier for each question).

When we get a row from this table from the database, it will be an instance of the other class - `Question`.

`Question` is called the *instance type* of the entity, because that's what we have instances of. `_Question` is the *persistent type* of the entity, because it declares what is stored in the database.

An instance type must *implement* its persistent type. This is how our instance type has the properties from the persistent type. Our instance type also inherits behavior that allows us to use it to represent rows in the database. The type parameter for `ManagedObject<T>` must be the persistent type; this tells the ORM which table to use.

!!! tip "Transient Properties"
    Properties declared in the instance type aren't stored in the database. This is different than properties in the persistent type. This behavior is useful for a number of reasons: providing tiny bits of logic, expanding a value into multiple columns, collapsing a value into a single column, etc. For example, a database table might have a `firstName` and `lastName`, but it's useful in some places to have a `fullName` property without having to store it in the database.

Defining a Context
---

Our application needs to know two things to execute database queries:

1. What is the data model (our collection of entities)?
2. What database are we connecting to?

Both of these things are determined when an application is first started. In `channel.dart`, add a new property `context` and update `prepare()`:

```dart
class QuizChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    logger.onRecord.listen((rec) => print("$rec ${rec.error ?? ""} ${rec.stackTrace ?? ""}"));

    final dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    final persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo(
      "quiz_user", "password", "localhost", 5432, "quiz");

    context = new ManagedContext(dataModel, persistentStore);
  }

  @override
  Controller get entryPoint {
    ...
```

`ManagedDataModel.fromCurrentMirrorSystem()` will find all of our `ManagedObject<T>` subclasses and 'compile' them into a data model. A `PostgreSQLPersistentStore` takes database connection information that it will use to connect and send queries to a database. Together, these objects are packaged up into a `ManagedContext`.

Once we have a context, we don't have to directly concern ourselves with the persistent store or data model. It will coordinate these two objects to execute queries and translate objects to and from the database. If an object has a reference to the context, it can execute queries on the database it coordinates. So, we'll want `QuestionController` to have access to the context.

In `question_controller.dart`, add a property and create a new constructor:

```dart
class QuestionController {
  QuestionController(this.context);

  ManagedContext context;
  // You can delete the list of questions if you like, we won't use it. But
  // the analyzer will yell at you for a bit.
  ...
```

The analyzer should tell us we have an error in our `channel.dart` file; the constructor for `QuestionController` now requires a `ManagedContext`. Update the `entryPoint` so that each time a new `QuestionController` is created, the context we created in the channel is passed to its constructor:

```dart
@override
Controller get entryPoint {
  final router = new Router();

  router
    .route("/questions/[:index]")
    .generate(() => new QuestionController(context));

  router
    .route("/example")
    .listen((request) async {
      return new Response.ok({"key": "value"});
  });

  return router;
}
```

Now that we've 'injected' this context into our `QuestionController` instances, they can execute database queries.

Executing Queries
---

Our operation methods in `QuestionController` currently return questions from an in-memory list. We will replace the implementation of these methods so that these questions are fetched from a PostgreSQL database. To get data from a database, we create and execute instances of `Query<T>` in our `ManagedContext`.

Let's start by replacing `getAllQuestions` in `question_controller.dart`. Make sure to import your `question.dart` file at the top:

```dart
import '../quiz.dart';
import '../model/question.dart';

class QuestionController extends RESTController {
  QuestionController(this.context);

  ManagedContext context;

  @Bind.get()
  Future<Response> getAllQuestions() async {
    final questionQuery = new Query<Question>(context);
    final databaseQuestions = await questionQuery.fetch();

    return new Response.ok(databaseQuestions);
  }

...
```

Here, we create an instance of `Query<Question>` and then execute its `fetch()` method. The type argument to `Query<T>` is an instance type; it lets the query know which table to fetch rows from. The context argument tells it which database to fetch it from. The `fetch()` execution method returns a `List<T>` of that instance type. That list gets returned as the body of the response.

Now, let's update `getQuestionAtIndex` to fetch a single question by its index from the database.

```dart
@Bind.get()
Future<Response> getQuestionAtIndex(@Bind.path("index") int index) async {
  final questionQuery = new Query<Question>(context)
    ..where.index = whereEqualTo(index);    

  final question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

This query does two interesting things. First, it uses the `where` property to filter questions that have the same `index` as the path variable; i.e., `/questions/1` will fetch only questions with an index of `1`. This works because the `where` property adds a SQL WHERE clause to the query. We'd get the following SQL:

```sql
SELECT index, description FROM _question WHERE index = 1;
```

The `where` property is actually an instance of `Question`, so it will have an `index` and `description` property. We apply *matchers* to those properties. A matcher is a function or constant that starts with the word `where` - like `whereEqualTo()`. By applying matchers, we specify which values and operators are used in the WHERE clause.

!!! tip "Matching All the Things"
    There are a lot of matchers available to build different queries. All matchers start with the word `where` and can be found by searching the [API reference](https://www.dartdocs.org/documentation/aqueduct/latest/).

The `fetchOne()` query execution method will return a single object that fulfills any matcher applied to the query's `where`. If no database row meets the criteria, `null` is returned. In that case, we return a 404 Not Found response.

We have now written code that fetches questions from a database instead of from in memory, but we don't have a database - yet.

!!! tip "Use fetchOne() on Unique Properties"
    If more than one object meets the criteria of a `fetchOne()`, an exception is thrown.
    It's only safe to use `fetchOne()` when applying a matcher to a unique property, like an entity's primary key.

Setting Up a Database
---

For development, you'll need to install a PostgreSQL server on your local machine. If you are on macOS, your best bet is to use [Postgres.app](http://postgresapp.com). This application starts a PostgreSQL instance when it is open, and closes it when the application is shut down. For other platforms, see [this page](https://www.postgresql.org/download/).

Once you have PostgreSQL installed and running, open a command line interface to it. If you are using `Postgres.app`, select the elephant icon in your status bar and then select `Open psql`. Otherwise, enter `psql` into the command-line.

!!! warning "If you installed Postgres.app"
    The `psql` command-line utility is inside the `Postgres.app` application bundle, so entering `psql` from the command-line won't find the executable. Once you open `psql` from the status bar item, you'll see the full path to `psql` on your machine.

In `psql`, create a new database and a user to manage it.

```sql
CREATE DATABASE quiz;
CREATE USER quiz_user WITH createdb;
ALTER USER quiz_user WITH password 'password';
GRANT all ON database quiz TO quiz_user;
```
aqueduct db generate
```

This will create a new *migration file*. A migration file runs a series of SQL commands to alter a database's schema. It is created in a new directory in your project named `migrations/`. Review the contents of `migrations/00000001_Initial.migration.dart`; you'll notice that it creates a new table with columns for each property of our persistent type, `_Question`.

Apply this migration file to our locally running `quiz` database with the following command in the project directory:

```dart
aqueduct db upgrade --connect postgres://quiz_user:password@localhost:5432/quiz
```

This command executes all of the migration files for a project, and in this case, that creates the `_Question` table. Now, we will add some question rows. Back in our `psql` terminal, run the following SQL commands:

```sql
\c quiz
INSERT INTO _question (description) VALUES ('How much wood could a woodchuck chuck?');
INSERT INTO _question (description) VALUES ('What is the tallest mountain in the world?');
```

Re-run your application with `aqueduct serve` and enter the following URLs into a browser:

```
http://localhost:8081/questions
http://localhost:8081/questions/1
http://localhost:8081/questions/9999
```

You should see the full list of questions, the first question, and then a 404 Not Found.

(You can now close `psql`.)

!!! note
    Notice that `/questions/1` now returns the first question, where previously `/questions/0` did. This is because PostgreSQL automatically generates a value for the primary key column of an inserted row, and that generation starts at 1 instead of 0.

## Inserting Data

A `Query<T>` can also insert, delete or update rows. Let's create an operation to "create a new question". This operation will be `POST /questions` and it will need to send a JSON object that represents a question in the body.

In `question_controller.dart`, add the following operation method:

```dart
@Bind.post()
Future<Response> createQuestion(@HTTPBody() Question question) async {
  final query = new Query<Question>()
    ..values.description = question.description;

  final insertedQuestion = await query.insert();

  return new Response.ok(insertedQuestion);
}
```

There's a bit going on here, so let's deconstruct it. First, we know this operation method is bound to `POST /questions` because:

1. The `@Bind.post()` metadata indicates this method responds to `POST`.
2. We've routed both `/questions` and `/questions/:index` to this controller.
2. There are no path variable bindings, so it is expected that path variable `index` is null, i.e. `/questions`.


An instance of `Question` will be passed to us as an argument. Its `description` will be set to the value of a `description` key in the JSON request body. So, if we made the following request:

```
POST /questions HTTP/1.1
Content-Type: application/json; charset=utf-8

{
    "description": "What is 10+10?"
}
```

The value of `question.description` in this method would be `What is 10+10?` (its `index` would be `null`). This value is set on the query `values`. Like `where`, `values` is an instance of the type being inserted. Any property set on it will be inserted into a new row. In our case, the `insert()` function executes the following SQL:

```sql
INSERT INTO _questions (description) VALUES ('What is 10+10?');
```

!!! tip "Query Construction"
    Properties like `values` and `where` prevent errors by type and name checking columns with the analyzer. They're also great for speeding up writing code because your IDE will autocomplete property names. There is [specific behavior](../db/advanced_queries.md) a query uses to decide whether it should include a value from these two properties in the SQL it generates.



Then, this method would add a new row to the `_Question` table; the value of its description column would be `What is 10+10?` and its index column would be the next auto-incremented integer.

The body of this request will be available in the `question` argument because it is bound to the body of request. When an argument has `@HTTPBody()` binding - and it

The `@HTTPBody()` binding will bind the body of the request to an instance of `Question`. We'll get passed that question as an argument to this method, where we assign its `description` to the `values.description` of the query.

The `values` property of a `Query<T>` works similar to the `where` property in that it has the same properties of the type being queried; the difference is `values` are values to be stored in the database. When we execute the query's `insert()`, a new row gets created in the database with the values that have been assigned.

The `insert()` method returns the `Question` from the database after it has been inserted, which we then return in the response body.






This creates a database named `quiz` that a user named `quiz_user` has access to. Our `PostgreSQLPersistentStore` created in `QuizChannel` is already set up to connect to this database, so make sure the names for the database, username and password all match up. (Keep this terminal open for now.)

The `quiz` database is currently empty - not only does it not have questions, it doesn't even have a table to store questions. We'll need to:

1. Create a `_Question` table in the `quiz` database.
2. Insert a few rows into that table.

Fortunately, Aqueduct has a command-line tool to manage a database schema. This tool will synchronize the entities in your application with the tables in a database. From the project directory, run the following command:

```
aqueduct db generate
```

This will create a new *migration file*. A migration file runs a series of SQL commands to alter a database's schema. It is created in a new directory in your project named `migrations/`. Review the contents of `migrations/00000001_Initial.migration.dart`; you'll notice that it creates a new table with columns for each property of our persistent type, `_Question`.

Apply this migration file to our locally running `quiz` database with the following command in the project directory:

```dart
aqueduct db upgrade --connect postgres://quiz_user:password@localhost:5432/quiz
```

This command executes all of the migration files for a project, and in this case, that creates the `_Question` table. Now, we will add some question rows. Back in our `psql` terminal, run the following SQL commands:

```sql
\c quiz
INSERT INTO _question (description) VALUES ('How much wood could a woodchuck chuck?');
INSERT INTO _question (description) VALUES ('What is the tallest mountain in the world?');
```

Re-run your application with `aqueduct serve` and enter the following URLs into a browser:

```
http://localhost:8081/questions
http://localhost:8081/questions/1
http://localhost:8081/questions/9999
```

You should see the full list of questions, the first question, and then a 404 Not Found.

(You can now close `psql`.)

!!! note
    Notice that `/questions/1` now returns the first question, where previously `/questions/0` did. This is because PostgreSQL automatically generates a value for the primary key column of an inserted row, and that generation starts at 1 instead of 0.

## Inserting Data

A `Query<T>` can also insert, delete or update rows. Let's create an operation to "create a new question". This operation will be `POST /questions` and it will need to send a JSON object that represents a question in the body.

In `question_controller.dart`, add the following operation method:

```dart
@Bind.post()
Future<Response> createQuestion(@HTTPBody() Question question) async {
  final query = new Query<Question>()
    ..values = question;

  final insertedQuestion = await query.insert();

  return new Response.ok(insertedQuestion);
}
```

There's a bit going on here, so let's deconstruct it. First, we know this operation method is bound to `POST /questions` because:

1. The `@Bind.post()` metadata indicates this method responds to `POST`.
2. We've routed both `/questions` and `/questions/:index` to this controller.
2. There are no path variable bindings, so the path variable `index` must be null, i.e. `/questions`.

An instance of `Question` will be passed to us as an argument. Its properties will be set to values from the JSON request body because of the `@HTTPBody()` binding. So, if we made the following request, the value of `question.description` would be `What is 10+10?` (its `index` would be `null`):

```
POST /questions HTTP/1.1
Content-Type: application/json; charset=utf-8

{
    "description": "What is 10+10?"
}
```

The `Question` from the request body is then set as the `values` of the `Query<T>`. Like `where`, `values` is an instance of the type being inserted. In our case, the `insert()` function executes the following SQL:

```sql
INSERT INTO _questions (description) VALUES ('What is 10+10?');
```

!!! tip "Query Construction"
    Properties like `values` and `where` prevent errors by type and name checking columns with the analyzer. They're also great for speeding up development because your IDE will autocomplete property names. There is [specific behavior](../db/advanced_queries.md) a query uses to decide whether it should include a value from these two properties in the SQL it generates.


Once the query's `insert()` is executed, this SQL command is run and the newly created row is returned as `insertedQuestion`. This instance contains a value for the generated primary key `index`, and is written to the response body that is returned for this request.

The more you know: Query Parameters and HTTP Headers
---

So far, we have bound methods, bodies, and path variables to operation methods in `QuestionController`. You can also bind query parameters and headers, too.

The operation method selected by an `RESTController` subclass is determined by only the bound HTTP method and path variables. Other types of binding - body, query, and header - don't impact which operation method gets selected for an operation. If one of these three kinds of bindings is not available in a request, a 400 Bad Request response is sent and the method is not called. In practice, this means that you shouldn't have separate operation methods for different variations of body, query and header bindings.


We'll allow the `getAllQuestions` method to take a query parameter named `contains`. If this query parameter is part of the request, we'll filter the questions on whether or not that question contains some substring. In `question_controller.dart`, update this method by adding an optional parameter named `containsSubstring`:

```dart
@Bind.get()
Future<Response> getAllQuestions({@Bind.query("contains") String containsSubstring}) async {
  var questionQuery = new Query<Question>();
  if (containsSubstring != null) {
    questionQuery.where.description = whereContainsString(containsSubstring);
  }
  var databaseQuestions = await questionQuery.fetch();
  return new Response.ok(databaseQuestions);
}
```

If an HTTP request has a `contains` query parameter, that value will be available in the `containsSubstring` variable when this method is invoked. Also, note that we first check `containsSubstring` to make sure it is not-null. If we simply assigned `null` to `description`, we'd be creating a matcher that checked to see if the `description` *contained* `null`.

!!! tip "RESTController Binding"
    For more information on binding, see [this guide](../http/rest_controller.md).

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

This test will pass, along with the rest of them. It's important to note that GET `/questions` without a `contains` query still yields the correct results. That is because the `Bind.query` argument was declared in the optional parameters portion of the operation method. If the parameter were in the required, positional set of parameters and the query string was not included, this request would respond with a 400. (The same positional vs. optional behavior is true of `Bind.header`s as well.)

Binding query and header parameters in a operation method is a good way to make your code more intentional and avoid boilerplate parsing code. Additionally, Aqueduct is able to generate documentation from method signatures - by using bindings, the documentation generator can add that information to the documentation.

## [Next: Relationships and Joins](model-relationships-and-joins.md)
