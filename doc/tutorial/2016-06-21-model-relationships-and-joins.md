---
layout: page
title: "4. Model Relationships and Joins"
category: tut
date: 2016-06-21 12:38:44
order: 4
---

This chapter expands on the [previous](executing-queries.html).

Model objects can also have relationships to other model objects. There are two types of relationships: to-one and to-many. Let's add an answer for each `Question` in the form of a to-one relationship. First, create a new file `lib/model/answer.dart` and define a new model object to represent an answer:

```dart
part of quiz;

class Answer extends Model<_Answer> implements _Answer {}
class _Answer {
  @primaryKey int id;
  String description;
}

```

Notice we created the persistent type, instance type and went ahead and created a special `ModelQuery`. Link this file back to the library in `lib/quiz.dart`.

```dart
part 'model/answer.dart';
```

Now that we have a model class that represents both a question and answer, we will set up a relationship between them. It logically makes sense that a 'question *has a* answer', so let's add that property to `_Question`, the persistent type of `Question`:

```dart
class _Question {
  @primaryKey int index;
  String description;
  Answer answer;
}
```

Yes, it was pretty much that simple. There is one more thing to do - for all relationships, we also must specify the *inverse relationship*. The inverse will be a property on `Answer` that points back to the `Question` it is the answer for. In `_Answer`, add the inverse:

```dart
class _Answer {
  @primaryKey int id;
  String description;

  @RelationshipInverse(#answer)
  Question question;
}
```

Notice that we added `RelationshipInverse` metadata. All relationship inverses must have this data - it specifies to the underlying database which table will have the foreign key reference and it also establishes whether the 'question has an answer', or the 'answer has a question'. We went with the non-Jeopardy version, so the `_Answer` has it. Also notice that the symbol of the property in `Question` - `answer` - is the argument to `RelationshipInverse`. A model object could be related in different ways to the same type of model object, and therefore we must hook up the two related properties in this way. (By the way, `InverseRelationship` columns are always indexed.)

`RelationshipInverse` also allows you to specify a delete rule and whether or not the property is required, i.e., not nullable. By default, all `RelationshipInverse` relationships' delete rules are `RelationshipDeleteRule.nullify` and are not required - this is the least destructive action. But, in this case, we want the every question to always have an answer and if we delete the question, the answer gets deleted along with it:

```dart
class _Answer {
  @primaryKey int id;
  String description;

  @RelationshipInverse(#answer, deleteRule: RelationshipDeleteRule.cascade, isRequired: true)
  Question question;
}
```

There is nothing extra to do for the 'has one' side of the relationship when setting these extra relationship attributes. Finally, we need to add `Answer` to the `DataModel` in `quiz_sink.dart`. (Also by the way, it is easy to write a function that simply reflects on your application to find all `Model` types for you so you don't have to remember to do this, but again, we're staying manual to understand the concepts.)

```dart
class QuizSink extends RequestSink {
  QuizSink(Map<String, dynamic> options) : super(options) {
    var dataModel = new DataModel([Question, Answer]);
    var persistentStore = new PostgreSQLPersistentStore.fromConnectionInfo("dart", "dart", "localhost", 5432, "dart_test");
    context = new ModelContext(dataModel, persistentStore);
  }
```

Now that we have defined this relationship, we can associate answers with questions and return them in our `/questions` endpoint. In `question_controller.dart`, let's update the queries also fetch the `Answer` for each `Question` and include it in the response JSON. First, for  `getAllQuestions`, set `includeInResultSet` to `true` for `matchOn`'s `answer`:

```dart
@httpGet getAllQuestions({String contains: null}) async {
  var questionQuery = new Query<Question>()
    ..matchOn.answer.includeInResultSet = true;

  if (contains != null) {
    questionQuery.matchOn.description = whereContains(contains);
  }

  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

Yeah, that was it. The SQL that gets built for this `Query` will join on the underlying answer table. Therefore, each `answer` property of every `Question` returned will have a valid `Answer` instance from the database. Model objects also know how to recursively serialize themselves, so you'll get the following JSON when fetching a question that has been joined with its answer:

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



The partial matcher here will just check to see if the 'answer' key is a map that contains a `String` 'description' value. The extraneous 'id' key won't cause a failure. If you run the tests now, this test will still fail - 'answer' is null because there are no answers in the database. Let's insert some in `setUpAll` of `question_controller_test.dart`:

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

Notice that we took the result of the question insert - which returns an instance of `Question` - and used it as the value of the `Query<Answer>`'s `question`. This will take the primary key value of the `question` and insert it into the foreign key column in the `Answer`. Now, it just so happens we have a full `Question` object that we just received from the database that we could set to that property. If we did, and instead had just the `index` of the `Question`, we'd do this instead:

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
  @primaryKey int index;
  String description;
  OrderedSet<Answer> answers;
}
```

(Note that `answers` was pluralized and therefore the `RelationshipInverse` side of the relationship would need to update its symbol. Other than that, the `RelationshipInverse` property and `Answer`s do not need to change.)

The type of all has-many relationships is an instance of `OrderedSet`, where the related type is the type argument. An `OrderedSet` acts just like a `List` - it has methods like `map` and `where` - but also has special behavior that allows it to be used in building `Query`s. When including a has-many relationship, you set the `includeInResultSet` property of the `OrderedSet` to true:

```dart
var query = new Query<Question>()
  ..matchOn.answers.includeInResultSet = true;
```

Each returned `Question` would also have an `OrderedSet` of `Answers`s in its `answers` property. You may also filter which answers are returned for each `Question` by nesting `matchOn` properties.

```dart
var query = new Query<Question>()
  ..matchOn.answers.includeInResultSet = true
  ..matchOn.answers.matchOn.isCorrect = whereEqualTo(true);
```

This would fetch all `Question`s and all of their correct answers. Note that if `includeInResultSet` was not set to `true`, this `Query` would not filter answers because it wouldn't fetch them at all!

An `OrderedSet` is serialized into a list of `Map`s, and therefore the encoded JSON will be an array of objects.
