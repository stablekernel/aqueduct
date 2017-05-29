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

Notice that we added `ManagedRelationship` metadata to `question`. Since relationships are two-sided, only one side needs to have this metadata (and in fact, only one side *can* have this metadata). The first argument is the name of the property on the other side of the relationship; this is what links the relationship together.

The property with `ManagedRelationship` metadata is actually a column in the database. More specifically, it is a foreign key column. So in this case, the `_Answer` table has a foreign key column named `question_index`. (The name is derived by taking the name of the relationship property and name of the primary key property on the other side and joining it with a `_`.) The `_Answer` table now has three columns: `id`, `description` and `question_index`.

The relationship property *without* `ManagedRelationship` metadata is *not* a column in the database. Instead, it represents an *entire row* in the database. Thus, the table `_Question` only has two columns: `index` and `description`.

`ManagedRelationship` also allows you to specify a delete rule and whether or not the property is required, i.e., not nullable. By default, the delete rule is `ManagedRelationshipDeleteRule.nullify` and not required - this is the least destructive action. But, in this case, we want every question to always have an answer and if we delete the question, the answer gets deleted along with it:

```dart
class _Answer {
  @primaryKey int id;
  String description;

  @ManagedRelationship(
    #answer, onDelete: ManagedRelationshipDeleteRule.cascade, isRequired: true)
  Question question;
}
```

Now that we have defined this relationship, we can associate answers with questions and return them in our `/questions` endpoint. In `question_controller.dart`, let's update the queries to fetch the `Answer` for each `Question` and include it in the response JSON. First, for `getAllQuestions`, use `joinOne()` to connect to `question.answer` for `where`'s `answer`:

```dart
@httpGet
Future<Response> getAllQuestions({@HTTPQuery("contains") String containsSubstring: null}) async {
  var questionQuery = new Query<Question>()
    ..joinOne((question) => question.answer);

  if (containsSubstring != null) {
    questionQuery.where.description = whereContainsString(containsSubstring);
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

The partial matcher here will just check to see if the 'answer' key is a map that contains a `String` 'description' value. The extraneous 'id' key won't cause a failure. If you run the tests now, this test will still fail - 'answer' in the JSON is null because there are no answers in the database. Let's insert some by replacing `setUp` in `question_controller_test.dart`:

```dart
// Don't forget to add this import, too!
import 'package:quiz/model/answer.dart';

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
      new Question()
        ..description = "How much wood can a woodchuck chuck?"
        ..answer = (new Answer()..description = "Depends"),
      new Question()
        ..description = "What's the tallest mountain in the world?"
        ..answer = (new Answer()..description = "Mount Everest")
    ];

    for (var question in questions) {
      var questionInsert = new Query<Question>()
          ..values = question;
      var insertedQuestion = await questionInsert.insert();

      var answerInsert = new Query<Answer>()
        ..values.description = question.answer.description
        ..values.question = insertedQuestion;
      await answerInsert.insert();
    }
  });
```

Notice that we accumulated all of the questions and answers into a list of questions where each has an answer (`questions`). Managed objects can be used just like normal objects, too.

Then, for each question, we inserted it and got a reference to the `insertedQuestion` back. The difference between each `Question` in `questions` and `insertedQuestion` is that the `insertedQuestion` will have its primary key value (`index`) set by the database. This allows the `Answer`s - which have to be inserted separately, because they are different tables - to specify which question they are the answer for.

At the time the answer is being inserted, the question in the database `insertedQuestion` does not yet have an answer - so asking it for its `answer.description` would yield null. Therefore, the `values.description` is set from the source of data created in `questions`, but the `question` must be set from `insertedQuestion` - which contains the actual `index` of the question.

Recall that a property with `ManagedRelationship` - like `Answer.question` - is actually a foreign key column. When setting this property with a `ManagedObject<T>`, the primary key value of that instance is sent as the value for the foreign key column. In this case, the `insertedQuestion` has valid values for both `description` and `index`. Setting the query's `values.question` to this instance ignores the `description` - it's not going to store it anyway - and sets the `index` of the answer being inserted.

Note, also, that the query to insert a question has `values` that contain an answer. These answers will be ignored during that insertion, because only the question is being inserted. Inserting or updating values will only operate on one table at a table - this is intentional explicit to avoid unintended consequences.

You could also set the answer's question with the following code:

```dart
insertQuery = new Query<Answer>()
  ..values.description = answersIterator.current
  ..values.question = (new Question()..index = 1);
```

But you couldn't do this, because `values.question` is null:

```dart
insertQuery = new Query<Answer>()
  ..values.description = answersIterator.current
  ..values.question.id = 1;
```

Now, running the tests against, the first one will succeed again. We'll leave it as an exercise to the user to update the remaining failing tests to check for an answer.

More on Joins and Relationships
---

Has-many relationships are also available. For example, if you wanted many answers for a question, it'd be declared like so:

```dart
class _Question {
  @managedPrimaryKey
  int index;

  String description;
  ManagedSet<Answer> answers;
}
```

The inverse relationship doesn't have to be updated - whether it is has-one or has-many is determined by whether or not property is a `ManagedSet<T>` or a subclass of `ManagedObject<T>`. For `ManagedSet<T>`, `T` must be a subclass of `ManagedObject<T>`. A `ManagedSet` acts just like a `List` - it has methods like `map` and `where` - but also has special behavior that allows it to be used in building `Query<T>`s. If you wish to join on `ManagedSet<T>` properties, the syntax is the same:

```dart
var query = new Query<Question>()
  ..joinMany((question) => question.answers);  
```

Each returned `Question` would also have a `ManagedSet` of `Answer`s in its `answers` property. You may also filter which answers are returned for each `Question`. A `joinMany` or `joinOne` creates a new `Query<T>` that has its own `where` property.

```dart
var query = new Query<Question>();
var join = query.joinMany((question) => question.answers)
  ..where.isCorrect = whereEqualTo(true);  
```

An `ManagedSet` is serialized into a `List` of `Map`s, and therefore the encoded JSON will be an array of objects.

## [Next: Deployment](deploying-and-other-fun-things.md)
