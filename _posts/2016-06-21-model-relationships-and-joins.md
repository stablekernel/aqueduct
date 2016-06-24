---
layout: default
title: "4. Model Relationships and Joins"
category: tut
date: 2016-06-21 12:38:44
order: 4
---

This chapter expands on the [previous](http://stablekernel.github.io/aqueduct/tut/executing-queries.html).

Model objects can also have relationships to other model objects. There are two types of relationships: to-one and to-many. Let's add an answer for each `Question` in the form of a to-one relationship. First, create a new file `lib/model/answer.dart` and define a new model object to represent an answer:

```dart
part of quiz;

class _Answer {
  @primaryKey
  int id;

  String description;
}
class Answer extends Model<_Answer> implements _Answer {}
class AnswerQuery extends ModelQuery<Answer> implements _Answer {}
```

Notice we created the persistent type, instance type and went ahead and created a special `ModelQuery`. Link this file back to the library in `lib/quiz.dart`.

```dart
part 'model/answer.dart';
```

Now that we have a model class that represents both a question and answer, we will set up a relationship between them. It logically makes sense that a 'question *has a* answer', so let's add that property to `_Question`, the persistent type of `Question`:

```dart
class _Question {
  @primaryKey
  int index;

  String description;

  @Relationship.hasOne("question")
  Answer answer;
}
```

We have declared a new persistent property, and its type is another `Model` object - `Answer`. The property is marked with `Relationship` metadata, indicating each `Question` will have *one* `Answer`. The single parameter for a `Relationship.hasOne` is called the *inverse key*. Whenever you declare a relationship, you must declare it in both persistent types that are involved in the relationship. The inverse key indicates the name of the property on the other class that represents this relationship.

So, let's set that up. In `_Answer`, add the inverse:

```dart
class _Answer {
  @primaryKey
  int id;

  String description;

  @Relationship.belongsTo("answer")
  Question question;
}
```

Notice that the inverse has a relationship type of `belongsTo`. The persistent type that has the `belongsTo` side of the relationship will contain the foreign key column. Notice that the exact names of the properties in the related classes are the same as the argument in the `Relationship` metadata. `belongsTo` relationship allow you to specify a delete rule and whether or not the property is required, i.e., not nullable. By default, all `belongsTo` relationships' delete rules are nullify and are not required - this is the least destructive action. But, in this case, we want the every question to always have an answer and if we delete the question, the answer gets deleted along with it:

```dart
class _Answer {
  @primaryKey
  int id;

  String description;

  @Relationship.belongsTo("answer", deleteRule: RelationshipDeleteRule.cascade, required: true)
  Question question;
}
```

There is nothing extra to do for the `hasOne` side of the relationship when setting these extra relationship attributes. (By the way, relationship columns are always indexed.) Finally, we need to add `Answer` to the `DataModel` in `pipeline.dart`. (Also by the way, it is easy to write a function that simply reflects on your application to find all `Model` types for you so you don't have to remember to do this, but again, we're staying manual to understand the concepts.)

Now that we have defined this relationship, we can associate answers with questions and return them in our `/questions` endpoint. In `question_controller.dart`, let's update the queries to join on the `Answer` table and include the answer in the response JSON. First, for get all questions:

```dart
@httpGet getAllQuestions({String contains: null}) async {
  var questionQuery = new QuestionQuery()
    ..answer = whereAnyMatch;
  if (contains != null) {
    questionQuery.description = whereContains(contains);
  }
  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

Yeah, that was it. The matcher `whereAnyMatch`, when applied to a `hasOne` or `hasMany` relationship property, will configure a join on the Answers table when fetching the questions. When the resulting model objects comes back, for each question, its `answer` property will be populated (if it has an answer). Model objects also know how to recursively serialize themselves, so you'll get the following JSON when fetching a question that has been joined with its answer:

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

Let's update our tests to ensure this works correctly. If you run your tests now, the two tests that get a list of `Question`s will fail because they don't expect an answer key in the JSON. Now, we don't really care about the 'id' of the answer at all, just its 'description'. Therefore, when we add to the HTTP body matcher to match the inner 'answer' object, it'd be great if we could just ignore it. That's why there is the `partial` matcher. A `partial` matcher will match a `Map`, but will only verify the values for each key in the partial matcher. Let's try that out by updating the first test for getting all questions:

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
  insertQuery = new AnswerQuery()
    ..values.description = answersIterator.current
    ..values.question = question;
  await insertQuery.insert();
}
```

Notice that we took the result of the question insert - which returns an instance of `Question` - and used it as the value of the `AnswerQuery`'s `question`. This will take the primary key value of the `question` and insert it into the foreign key column in the `Answer`. Now, it just so happens we have a full `Question` object that we just received from the database that we could set to that property. If we did, and instead had just the `index` of the `Question`, we'd do this instead:

```dart
insertQuery = new AnswerQuery()
  ..values.description = answersIterator.current
  ..values.question = (new Question()..index = 1);
```

Now, running the tests against, the first one will succeed again. Update the last test that checks a list of questions when sending a 'contains' query parameter:

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

As relationships and joins are a complex topic, you may want to read the corresponding guide on them to get a full understanding of how `aqueduct` supports them.
However, it is important to note that to-many relationships are also available. For example, if you wanted many answers for a question,
you'd declare the relationship property as `hasMany` and make it a `List` of the related instance type:

```dart
class _Question {
  @primaryKey
  int index;

  String description;

  @Relationship.hasMany("question")
  List<Answer> answers;
}
```

Note that `answers` was pluralized and therefore the `belongsTo` side of the relationship would need to update its inverse key.

Join queries can be nested indefinitely, and can have their own matchers applied to them using the same syntax. For example, this would
return a social media user with a specific ID, all of their posts in the since the beginning of 2016, and all of the people that have liked their post who have the name 'Fred':

```dart
var query = new UserQuery()
    ..id = whereEqualTo(24)
    ..posts.single.postDate = whereGreaterThanEqualTo(new DateTime(2016).toUtc())
    ..posts.single.likers.single.name = whereContains("Fred");
```

Which, when fetched and then encoded to JSON, would look something like this:

```json
{
    "id" : 24,
    "name" : "Somebody",
    "posts" : [{
        "id" : 4,
        "postDate" : "2016-01-02...",
        "likers" : [{
            "id" : 18,
            "name" : "Fred Freddieson"
        ]}
    }]
}
```
