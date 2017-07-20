# ManagedObject Relationships

Managed objects can also have relationships to other managed objects. There are two types of relationships: to-one and to-many. Let's add an answer for each `Question` in the form of a to-one relationship. First, create a new file `lib/model/answer.dart` and define a new managed object to represent an answer:

```dart
import '../quiz.dart';

class Answer extends ManagedObject<_Answer> implements _Answer {}
class _Answer {
  @managedPrimaryKey
  int id;

  String description;
}
```

Now that we have a managed object that represents both a question and answer, we will set up a relationship between them. It logically makes sense that a 'question *has an* answer', so let's add that property to `_Question`, the persistent type of `Question`:

```dart
// Don't miss this new import!
import 'answer.dart';

class _Question {
  @managedPrimaryKey
  int index;

  String description;
  Answer answer;
}
```

For all relationships, we also must specify the *inverse relationship*. The inverse will be a property on `_Answer` that points back to the `Question` it is the answer for. In `_Answer`, add the inverse:

```dart
// Don't miss this new import, either!
import 'question.dart';

class _Answer {
  @managedPrimaryKey
  int id;
  String description;

  @ManagedRelationship(#answer)
  Question question;
}
```

Notice that we added `ManagedRelationship` metadata to the property `question`. Since relationships are two-sided, only one side needs to have this metadata (and in fact, only one side *can* have this metadata). The first argument is the name of the property on the other side of the relationship; this is what links the relationship together.

The property with `ManagedRelationship` metadata maps to the foreign key column in the database table. The table `_Answer` has a foreign key column named `question_index`. (The name is derived by taking the name of the relationship property and name of the primary key property on the other side and joining it with a `_`.) The `_Answer` table now has three columns: `id`, `description` and `question_index`.

The relationship property *without* `ManagedRelationship` metadata is *not* a column in a table. Instead, it represents an *entire row* in another table. Thus, the table `_Question` only has two columns: `index` and `description`.

`ManagedRelationship` also allows you to specify a delete rule and whether or not the property is required, i.e., not nullable. By default, the delete rule is `ManagedRelationshipDeleteRule.nullify` and not required - this is the least destructive action. But, in this case, we want every question to always have an answer and if we delete the question, the answer gets deleted along with it:

```dart
class _Answer {
  @primaryKey
  int id;
  String description;

  @ManagedRelationship(
    #answer, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  Question question;
}
```

Now that we have defined this relationship, we can associate answers with questions and return them in our `/questions` endpoint. In `question_controller.dart`, let's update the queries to fetch the `Answer` for each `Question` and include it in the response JSON. First, for `getAllQuestions`, use `join()` to include the answers:

```dart
@httpGet
Future<Response> getAllQuestions({@HTTPQuery("contains") String containsSubstring: null}) async {
  var questionQuery = new Query<Question>()
    ..join(object: (question) => question.answer);

  if (containsSubstring != null) {
    questionQuery.where.description = whereContainsString(containsSubstring);
  }

  var questions = await questionQuery.fetch();
  return new Response.ok(questions);
}
```

And same for `getQuestionAtIndex`:

```dart
@httpGet
Future<Response> getQuestionAtIndex(@HTTPPath("index") int index) async {
  var questionQuery = new Query<Question>()
    ..join(object: (question) => question.answer)
    ..where.index = whereEqualTo(index);

  var question = await questionQuery.fetchOne();

  if (question == null) {
    return new Response.notFound();
  }
  return new Response.ok(question);
}
```

The SQL that gets built for this `Query<T>` will join on the underlying `_Answer` table. Therefore, each `answer` property of every `Question` returned will have a valid `Answer` instance from the database. Managed objects also know how to serialize their relationship properties, so you'll get the following JSON when fetching a question that has been joined with its answer:

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

Let's update our tests to ensure this works correctly. If you run your tests now, the two tests that get a list of `Question`s will fail because they don't expect an answer key in the JSON. Now, we don't really care about the 'id' of the answer at all, just its 'description'. That's why there is the `partial` matcher. A `partial` matcher will match a `Map`, but will only verify the values for the specified keys. Any other key-value pairs are just ignored. Update the following tests:

```dart
test("/questions returns list of questions", () async {
  expectResponse(
    await app.client.request("/questions").get(),
    200,
    body: allOf([
      hasLength(greaterThan(0)),
      everyElement(partial({
        "description": endsWith("?"),
        "answer": partial({
          "description": isString
        })
      }))]));
});

test("/questions/index returns a single question", () async {
  expectResponse(
    await app.client.request("/questions/1").get(),
    200,
    body: partial({
      "description": endsWith("?"),
      "answer": partial({
        "description": isString
      })
    }));
});

test("/questions returns list of questions filtered by contains", () async {
  var request = app.client.request("/questions?contains=mountain");
  expectResponse(
    await request.get(),
    200,
    body: [{
      "index" : greaterThanOrEqualTo(0),
      "description" : "What's the tallest mountain in the world?",
      "answer": partial({
        "description": "Mount Everest"
      })
    }]);
});
```

If you run the tests now, this test will still fail - 'answer' in the JSON is null because there are no answers in the test database. Let's insert some by adding to `setUpAll` in `question_controller_test.dart`:

```dart
// Don't forget to add this import, too!
import 'package:quiz/model/answer.dart';

void main() {
  setUpAll(() async {
    await app.start();

    var questions = [
      new Question()
        ..description = "How much wood can a woodchuck chuck?"
        ..answer = (new Answer()..description = "Depends"),
      new Question()
        ..description = "What's the tallest mountain in the world?"
        ..answer = (new Answer()..description = "Mount Everest"),
    ];

    await Future.forEach(questions, (Question q) async {
      var query = new Query<Question>()
          ..values = q;
      var insertedQuestion = await query.insert();

      var answerQuery = new Query<Answer>()
        ..values.description = q.answer.description
        ..values.question = insertedQuestion;
      await answerQuery.insert();
      return insertedQuestion;
    });
  });
```

Notice that we accumulated all of the questions and answers into a list of questions where each has an answer (`questions`). Managed objects can be used just like normal objects, too.

Then, for each question, we inserted it and got a reference to the `insertedQuestion` back. The difference between each `Question` in `questions` and `insertedQuestion` is that the `insertedQuestion` will have its primary key value (`index`) set by the database. This allows the `Answer`s - which have to be inserted separately, because they are different tables - to specify which question they are the answer for.

Recall that a property with `ManagedRelationship` - like `Answer.question` - is actually a foreign key column. When setting this property with a `ManagedObject<T>`, the primary key value of that instance is sent as the value for the foreign key column. In this case, the `insertedQuestion` has valid values for both `description` and `index`. Setting the query's `values.question` to this instance ignores the `description` - it's not going to store it anyway - and sets the `index` of the answer being inserted.

Note, also, that the query to insert a question has `values` that contain an answer. These answers will be ignored during that insertion, because only the question is being inserted. Inserting or updating values will only operate on one table at a table - this is intentional explicit to avoid unintended consequences.

The tests will now pass.

More on Joins and Relationships
---

Relationships can also be 'has-many'. For example, if you wanted many answers for a question, we'd use a `ManagedSet<T>`:

```dart
class _Question {
  @managedPrimaryKey
  int index;

  String description;
  ManagedSet<Answer> answers;
}
```

The inverse relationship doesn't have to be updated. For `ManagedSet<T>`, `T` must be a subclass of `ManagedObject<T>`. A `ManagedSet` acts just like a `List` - it has methods like `map` and `where` - but also has special behavior that allows it to be used in building `Query<T>`s. If you wish to join on `ManagedSet<T>` properties, the syntax is similar:

```dart
var query = new Query<Question>()
  ..join(set: (question) => question.answers);  
```

Each returned `Question` would also have a `ManagedSet` of `Answer`s in its `answers` property. You may also filter which answers are returned for each `Question`. A `join` creates a new `Query<T>` that has its own `where` property.

```dart
var query = new Query<Question>();

query.join(set: (question) => question.answers)
  ..where.isCorrect = whereEqualTo(true);  

var questionsWithCorrectAnswers = await query.fetch();
```

An `ManagedSet` is serialized into a `List` of `Map`s, and therefore the encoded JSON will be an array of objects.

## [Next: Deployment](deploying-and-other-fun-things.md)
