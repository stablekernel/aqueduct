---
layout: page
title: "4. ManagedObject Relationships and Joins"
category: tut
date: 2016-06-21 12:38:44
order: 4
---

This chapter expands on the [previous](executing-queries.html).

Managed objects can also have relationships to other managed objects. There are two types of relationships: to-one and to-many. Let's add an answer for each `Question` in the form of a to-one relationship. First, create a new file `lib/model/answer.dart` and define a new managed object to represent an answer:

```dart
part of quiz;

class Answer extends ManagedObject<_Answer> implements _Answer {}
class _Answer {
  @managedPrimaryKey int id;
  String description;
}

```

Notice we created the persistent type and subclass of `ManagedObject`. Link this file back to the library in `lib/quiz.dart`.

```dart
part 'model/answer.dart';
```

Now that we have a managed object that represents both a question and answer, we will set up a relationship between them. It logically makes sense that a 'question *has a* answer', so let's add that property to `_Question`, the persistent type of `Question`:

```dart
class _Question {
  @managedPrimaryKey int index;

  String description;
  Answer answer;
}
```

Yes, it was pretty much that simple. There is one more thing to do - for all relationships, we also must specify the *inverse relationship*. The inverse will be a property on `_Answer` that points back to the `Question` it is the answer for. In `_Answer`, add the inverse:

```dart
class _Answer {
  @managedPrimaryKey int id;
  String description;

  @ManagedRelationship(#answer) Question question;
}
```

Notice that we added `ManagedRelationship` metadata to `question`. All relationships are two-sided. The relationship property that has 'has-one' or 'has-many' semantics must not have `ManagedRelationship` metadata, and the other side must have this metadata. The relationship property with this metadata maps to a foreign key column in the database. The relationship property without this metadata maps to a *row or rows* in the database and the underlying database table does not have a column.

Notice the first argument to `ManagedRelationship` - it is the name of the relationship property on `_Question`. This allows the data model to understand which two properties link a managed object's relationships together.

`ManagedRelationship` also allows you to specify a delete rule and whether or not the property is required, i.e., not nullable. By default, the delete rule is `ManagedRelationshipDeleteRule.nullify` and are not required - this is the least destructive action. But, in this case, we want every question to always have an answer and if we delete the question, the answer gets deleted along with it:

```dart
class _Answer {
  @primaryKey int id;
  String description;

  @ManagedRelationship(#answer, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  Question question;
}
```

There is nothing extra to do for the 'has one' side of the relationship when setting these extra relationship attributes. Finally, we need to add `Answer` to the `ManagedDataModel` of the application. It'll get obnoxious to keep adding every new managed object subclass to the data model, so there is a handy constructor for that purpose. Update the constructor in `quiz_request_sink.dart`.


```dart
class QuizRequestSink extends RequestSink {
  QuizRequestSink(Map<String, dynamic> options) : super(options) {
    var dataModel = new ManagedDataModel.fromPackageContainingType(QuizRequestSink);

    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    context = new ManagedContext(dataModel, persistentStore);
  }
```

The constructor `ManagedDataModel.fromPackageContainingType` will reflect on the package that `QuizRequestSink` comes from and find all subclasses of `ManagedObject` for you.

Now that we have defined this relationship, we can associate answers with questions and return them in our `/questions` endpoint. In `question_controller.dart`, let's update the queries to fetch the `Answer` for each `Question` and include it in the response JSON. First, for `getAllQuestions`, set `includeInResultSet` to `true` for `matchOn`'s `answer`:

```dart
@httpGet getAllQuestions({@HTTPQuery("contains") String containsSubstring: null}) async {
  var questionQuery = new Query<Question>()
    ..matchOn.answer.includeInResultSet = true;

  if (containsSubstring != null) {
    questionQuery.matchOn.description = whereContains(containsSubstring);
  }

  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

Yeah, that was it. The SQL that gets built for this `Query<T>` will join on the underlying `_Answer` table. Therefore, each `answer` property of every `Question` returned will have a valid `Answer` instance from the database. Managed objects also know how to serialize their relationship properties, so you'll get the following JSON when fetching a question that has been joined with its answer:

```json
{
  "index" : 1,
  "description" : "A question?",
  "answer" : {
      "id" : 1,
      "description" : "An answer"
  }
}
```

Let's update our tests to ensure this works correctly. If you run your tests now, the two tests that get a list of `Question`s will fail because they don't expect an answer key in the JSON. Now, we don't really care about the 'id' of the answer at all, just its 'description'. Therefore, when we add to the HTTP body matcher to match the inner 'answer' object, it'd be great if we could just ignore it. That's why there is the `partial` matcher. A `partial` matcher will match a `Map`, but will only verify the values for the specified keys. Any other key-value pairs are just ignored. Let's try that out by updating the first test for getting all questions:

```dart
test("/questions returns list of questions", () async {
    var response = await client.request("/questions").get();
    expect(response, hasResponse(200, everyElement({
        "index" : greaterThanOrEqualTo(0),
        "description" : endsWith("?"),
        "answer" : partial({
          "description" : isString
        })
    })));
    expect(response.decodedBody, hasLength(greaterThan(0)));
  });
```

The partial matcher here will just check to see if the 'answer' key is a map that contains a `String` 'description' value. The extraneous 'id' key won't cause a failure. If you run the tests now, this test will still fail - 'answer' in the JSON is null because there are no answers in the database. Let's insert some in `setUpAll` of `question_controller_test.dart`:

```dart
var questions = [
  "How much wood can a woodchuck chuck?",
  "What's the tallest mountain in the world?"
];
var answersIterator = [
  "Depends on if they can",
  "Mount Everest"
].iterator;

for (var question in questions) {
  var insertQuery = new Query<Question>()
    ..values.description = question;
  question = await insertQuery.insert();

  answersIterator.moveNext();
  insertQuery = new Query<Answer>()
    ..values.description = answersIterator.current
    ..values.question = question;
  await insertQuery.insert();
}
```

Notice that we took the result of the `Question` insert - which returns an instance of `Question` - and used it as a value in the `Answer` insert query. This will take the primary key value of the `question` and insert it into the foreign key column in the `Answer`. Now, it just so happens we have a full `Question` object that we just received from the database that we could set to that property. If we didn't, and instead had just the `index` of the `Question`, we'd do this instead:

```dart
insertQuery = new Query<Answer>()
  ..values.description = answersIterator.current
  ..values.question = (new Question()..index = 1);
```

Now, running the tests against, the first one will succeed again. Update the test that checks a list of questions when sending a 'contains' query parameter to also ensure the answer is there:

```dart
test("/questions returns list of questions filtered by contains", () async {
  var response = await client.request("/questions?contains=mountain").get();
  expect(response, hasResponse(200, [{
      "index" : greaterThanOrEqualTo(0),
      "description" : "What's the tallest mountain in the world?",
      "answer" : partial({
        "description" : "Mount Everest"
      })
  }]));
  expect(response.decodedBody, hasLength(1));
});
```

All tests are back to passing.

More on Joins and Relationships
---

Has-many relationships are also available. For example, if you wanted many answers for a question, it'd be declared like so:

```dart
class _Question {
  @managedPrimaryKey int index;
  String description;
  ManagedSet<Answer> answers;
}
```

Now that `answer` has been pluralized to `answer`, we would also have to update the inverse relationship key in `_Answer`:

```dart
class _Answer {
  @managedPrimaryKey int id;

  String description;

  @ManagedRelationship(#answers, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  Question question;
}
```

The type of has-many relationships is an instance of `ManagedSet<T>`, where `T` is the related type. An `ManagedSet` acts just like a `List` - it has methods like `map` and `where` - but also has special behavior that allows it to be used in building `Query<T>`s. When including a has-many relationship, you set the `includeInResultSet` property of the `ManagedSet` to true:

```dart
var query = new Query<Question>()
  ..matchOn.answers.includeInResultSet = true;
```

Each returned `Question` would also have a `ManagedSet` of `Answer`s in its `answers` property. You may also filter which answers are returned for each `Question` by nesting `matchOn` properties.

```dart
var query = new Query<Question>()
  ..matchOn.answers.includeInResultSet = true
  ..matchOn.answers.matchOn.isCorrect = whereEqualTo(true);
```

This would fetch all `Question`s and all of their correct answers. Note that if `includeInResultSet` was not set to `true`, this `Query<T>` would not filter answers because it wouldn't fetch them at all!

An `ManagedSet` is serialized into a `List` of `Map`s, and therefore the encoded JSON will be an array of objects.

## [Next: Deployment](deploying-and-other-fun-things.html)
