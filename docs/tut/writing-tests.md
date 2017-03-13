
# Testing Aqueduct Applications

One of the core principles of Aqueduct is efficient testing. While opening up your browser and typing in a URL can verify the code you just wrote succeeds, it's not a very reliable way of testing software. We'll also run into some dead-ends when we test HTTP requests that use an HTTP method other than GET. Therefore, there are some helpful utilities for writing tests built into Aqueduct.

(As a note, testing Dart in Atom is not well supported - yet. Once you get past this tutorial, it is highly recommended you download IntelliJ IDEA Community Edition for better test support. Most importantly, Aqueduct's style of testing requires that test files are not run in parallel - and Atom only runs them in parallel. In the meantime, you can use the command line and run the tests serially using the command `pub run test -j 1`.)

In general, testing in Dart is simple: in a file that ends with `_test.dart`, you write a `main` function and use the `test` function register a test. Each test is a closure that runs some code and has expectations. For example, this code would test that 1 + 1 = 2:

```dart
import 'package:test/test.dart';

void main() {
  test("1+1 = 2", () {
    expect(1 + 1, equals(2));
  });
}
```

Tests are made possible by the `test` package which you'll need to claim as a dependency. In `quiz/pubspec.yaml`, add it as a development dependency by adding the following two lines to the end of the file:

```
dev_dependencies:
  test: any
```

Now, get the dependencies again by right-clicking on any project file and selecting 'Pub Get'. (Or run `pub get` from the command line in the `quiz` directory.)

Restructuring quiz
---

Last chapter, we just threw everything in a single file to get started. We should really get things structured a bit more. The suggested approach is to separate `RequestController`s into their own files. These files should live in `lib/controller`. The `RequestSink` subclass should be in its own file, too, but directly under `lib`.

Create a new directory, `lib/controller` and add a new file `question_controller.dart` to it. Create a new file in `lib` named `sink.dart`.

Now, we'll move some code around. The full contents of each file will be listed here to make sure nothing gets lost. There are three total source files in the project. Change the file `quiz.dart` to only contain:

```dart
export 'dart:async';
export 'package:aqueduct/aqueduct.dart';

export 'sink.dart';
```

Move the implementation of `QuestionController` to `controller/question_controller.dart` and import the top-level file:

```dart
import 'package:quiz/quiz.dart';

class QuestionController extends HTTPController {
  var questions = [
    "How much wood can a woodchuck chuck?",
    "What's the tallest mountain in the world?"
  ];

  @httpGet
  Future<Response> getAllQuestions() async {
    return new Response.ok(questions);
  }

  @httpGet
  Future<Response> getQuestionAtIndex(@HTTPPath("index") int index) async {
    if (index < 0 || index >= questions.length) {
      return new Response.notFound();
    }

    return new Response.ok(questions[index]);
  }
}
```  

Move `QuizRequestSink` to `sink.dart`:

```dart
import 'package:quiz/quiz.dart';
import 'controller/question_controller.dart';

class QuizRequestSink extends RequestSink {
  QuizRequestSink(ApplicationConfiguration options) : super (options);

  @override
  void setupRouter(Router router) {
    router
      .route("/questions/[:index(\\d+)]")
      .generate(() => new QuestionController());
  }
}
```

It is important that there is a top-level library file (`quiz.dart`) that exports the file that contains the `RequestSink` subclass, otherwise, the `aqueduct` executable won't be able to find it and start your application. Files that declare `RequestController` subclasses should be imported in `sink.dart`, since that's the only place they'll get used.

Additionally, the top-level library file *must* be named the same as the project - here, `quiz.dart`. The name of the project is is `name` key in `pubspec.yaml`.

You can double-check that your changes worked by running `aqueduct serve` from the project directory. The full project structure should be:

```
pubspec.yaml
lib/
  quiz.dart
  sink.dart
  controller/
    question_controller.dart
```  

Writing Tests
---

We'd like to ensure that when we hit the `/questions` endpoint, we get a response with questions. What does that mean? Well, that is up to us. But, let's say that 'questions' means 'a list of strings that all end in a question mark'.

In Dart, tests are stored in a top-level `test` directory. Create that directory in `quiz`. Then, add a new file to it named `question_controller_test.dart`. (Tests must end in `_test.dart` and live in the `test` directory for the tools to find them without you having to specify their path.) In this file, import the following:

```dart
import 'package:quiz/quiz.dart';
import 'package:test/test.dart';
import 'package:aqueduct/test.dart';
import 'package:aqueduct/aqueduct.dart';
```

The way Aqueduct accomplishes testing is by starting an entire application, running the tests, then stopping the application. The library `aqueduct/test` has helpful utilities for testing Aqueduct applications. Declare a `setUp` and `tearDown` method to run before and after each test. After the import statements, add a `main` function with the appropriate setup and teardown code:

```dart
void main() {
  var app = new Application<QuizRequestSink>();

  setUp(() async {
    await app.start(runOnMainIsolate: true);
  });

  tearDown(() async {
    await app.stop();
  });
}
```

The `Application` type has a type argument that must be a subclass of `RequestSink` - specifically, the `RequestSink` of your project. When running the application through `aqueduct serve`, an instance of `Application<T>` is created for you. Running tests, you create it and start it yourself in `setup` and stop it `tearDown`. (In order for your tests to shut down properly, the application must be stopped in `tearDown`.)

Notice also that `start` takes an optional argument, `runOnMainIsolate`. When this argument is true, an instance of your `RequestSink` is created on the main isolate and requests are received on the same isolate running the tests. This behavior is different than when using `aqueduct serve`, where one or more additional isolates are created and each has an instance of the `RequestSink` that is accepting requests.

During testing, running the application on the main isolate is very important. We'll see why a bit later, but the general idea is that your tests have access to the properties of a `RequestSink` if and only if it is running on the main isolate.

Now, we need to add a test to verify that hitting the `/questions` endpoint does return our definition of 'questions'. In Aqueduct, there is a utility called a `TestClient` to make this a lot easier. At the top of your main function, but after we create the application instance, declare a new variable:

```dart
void main() {
  var app = new Application<QuizRequestSink>();
  var client = new TestClient(app);
...
```

A `TestClient` will execute HTTP requests on your behalf in your tests, and is configured to point at the running application. Testing an Aqueduct application is generally two steps: make a request and then verify you got the response you wanted. Let's create a new test and do the first step. Near the end of main, add the following test:

```dart
void main() {
  ...

  test("/questions returns list of questions", () async {
    var response = await client.request("/questions").get();
  });
}
```

If you run this test file now, an instance of your application will spin up on the main isolate, and your first test will execute a GET `http://localhost:8081/questions`, then your application will be torn down. Of course, we don't verify anything about the response, so we should actually do something there.

The value of `response` in the previous code snippet is an instance of `TestResponse`. Dart tests use the Hamcrest style matchers in their expectations. There are built-in matchers in Aqueduct for setting up and matching expectations on `TestResponse` instances. For example, if we wanted to verify that we got a 404 back, we'd simply do:

```dart
  expect(response, hasStatus(404));
```

But here, we want to verify that we get back a 200 and that the response body is a list of questions. Add the following code to the end of the test:

```dart
test("/questions returns list of questions", () async {
  var response = await client.request("/questions").get();
  expect(response, hasResponse(200, everyElement(endsWith("?"))));
});
```

Now, make sure you shut down your application if you were running it from a previous chapter. To run a test file in Atom, you can do two things: manually hit Cmd-Shift-P and type in run test or use the keyboard shortcut, Cmd-Option-Ctrl-T. The test results will appear in a panel. (Make sure you save your test file first!  Atom currently isn't great at displaying test results. A more powerful option is IntelliJ IDEA Community Edition, but Atom is a lot friendlier for a tutorial.)

You should see the string 'All tests passed!' in your test results panel.

There's one little issue here: the `everyElement` matcher ensures each element passes the inner matcher (`endsWith`). However, if this response returned an empty list of questions, the inner matcher would never run and the test would pass. Let's also verify that there is at least one question, too:

```dart
test("/questions returns list of questions", () async {
  var response = await client.request("/questions").get();
  expect(response, hasResponse(200, everyElement(endsWith("?"))));
  expect(response.decodedBody, hasLength(greaterThan(0)));
});

```
What sort of wizardry is this?
---

The `hasResponse` matcher takes two arguments: a status code and a 'body matcher'. If the response's status code matches the first argument of `hasResponse` - 200 in this case - the matcher will move on to the body. The response's HTTP body will be decoded according to its `Content-Type` header. In this example, the body is a JSON list of strings, and therefore it will be decoded into a Dart list of strings.

Next, the decoded body is matched against the body matcher. There are a lot of built-in matchers - see the documentation for the test package [here](https://www.dartdocs.org/documentation/test/latest) - and `everyElement` and `endsWith` are two examples. `everyElement` verifies that the decoded body is a list, and then runs the `endsWith` matcher on every string in that list. Since every string ends with ?, this matcher as a whole will succeed.

Let's write two more tests - first, that getting a specific question returns a question (a string with a question mark at the end) and then a test that ensures a question outside of the range of questions will return a 404. Add the following two tests inside the main function:

```dart
test("/questions/index returns a single question", () async {
  var response = await client.request("/questions/1").get();
  expect(response, hasResponse(200, endsWith("?")));
});

test("/questions/index out of range returns 404", () async {
  var response = await client.request("/questions/100").get();
  expect(response, hasStatus(404));
});
```

Run the tests against, and they should all pass.

## [Next Chapter: Executing Database Queries](executing-queries.md)
