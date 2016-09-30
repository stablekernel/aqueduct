---
layout: page
title: "2. Writing Tests"
category: tut
date: 2016-06-20 09:38:12
order: 2
---

This chapter expands on the [previous](getting-started.html).

One of the core principles of Aqueduct is efficient testing. While opening up your browser and typing in a URL can verify the code you just wrote succeeds, it's not a very reliable way of testing software. We'll also run into some dead-ends when we test HTTP requests that use an HTTP method other than GET. Therefore, there are some helpful utilities for writing tests built into Aqueduct.

(As a note, testing Dart in Atom is not well supported - yet. Once you get past this tutorial, it is highly recommended you download IntelliJ IDEA Community Edition for better test support. Most importantly, Aqueduct's style of testing requires that test files are not run in parallel - and Atom only runs them in parallel. In the meantime, you can use the command line and run the tests serially using the command `pub run test -j 1`.)

In general, testing in Dart is simple: you write a `main` function and use the `test` function register a test. Each test is a closure that runs some code and has expectations. For example, this code would test that 1 + 1 = 2:

```dart
import 'package:test/test.dart';

void main() {
  test("1+1 = 2", () {
    expect(1 + 1, equals(2));
  });
}
```

Tests are made possible by the `test` package which you'll need to claim as a dependency. In `quiz/pubspec.yaml`, add it as a development dependency by adding the following two lines to the end of the file:

```yaml
dev_dependencies:
  test: any
```

Now, get the dependencies again by right-clicking on any project file and selecting 'Pub Get'. (Or run `pub get` from the command line in the `quiz` directory.)

Restructuring quiz
---

Last chapter, we just threw everything in a single file to get started. To test, we really need to add some structure to our project. In the top-level directory `quiz`, create a new directory named `lib`. In this directory, create a new file named `quiz.dart`. This is your library file and it will contain references to every file in your project and packages you wish to import. Add the following:

```dart
library quiz;

import 'package:aqueduct/aqueduct.dart';
export 'package:aqueduct/aqueduct.dart';

part 'controller/question_controller.dart';
part 'quiz_sink.dart';
```

You'll get some warnings because `controller/question_controller.dart` and `quiz_sink.dart` don't yet exist. Let's create those. Create a new directory at `quiz/lib/controller` and add the file `question_controller.dart` to that directory. At the top of this file, link this 'part' back to the library file and then copy and paste the `QuestionController` class from `bin/quiz.dart` into it:

```dart
part of quiz;

class QuestionController extends HTTPController {
  var questions = [
		"How much wood can a woodchuck chuck?",
		"What's the tallest mountain in the world?"
	];

  @httpGet getAllQuestions() async {
    return new Response.ok(questions);
  }

  @httpGet getQuestionAtIndex(@HTTPPath("index") int index) async {
    if (index < 0 || index >= questions.length) {
      return new Response.notFound();
    }

    return new Response.ok(questions[index]);
  }
}
```

Next, create a new file at `lib/quiz_sink.dart`, link this part back to the library, and copy and paste the `QuizSink` class into this file:

```dart
part of quiz;

class QuizSink extends RequestSink {
  QuizSink(Map<String, dynamic> options) : super(options);

  void addRoutes() {
    router
      .route("/questions/[:index(\\d+)]")
      .generate(() => new QuestionController());
  }
}
```

Now that you've split up the project across multiple files, we no longer need the `quiz.dart` file in `bin/`, so delete it. (Don't delete the `quiz.dart` file in `lib/`!) Create a new file in `bin/` named `start.dart` Add the startup `main` function to that file:

```dart
import 'package:quiz/quiz.dart';

void main() {
  var app = new Application<QuizSink>();

  app.start();
}
```

Note that we import `quiz.dart` and since the `quiz` library defined in this file exports Aqueduct, any file that imports `quiz.dart` will also import Aqueduct. Finally, get your dependencies again to get your project to recognize that `quiz` is now a library package. You can ensure that everything still works by running `bin/start.dart` again and typing a URL into your browser.

Writings Tests
---

We'd like to ensure that when we hit the `/questions` endpoint, we get a response with questions. What does that mean? Well, that is up to us. But, let's say that 'questions' means 'a list of strings that all end in a question mark'.

In Dart, tests are stored in a top-level `test` directory. Create that directory in `quiz`. Then, add a new file to it named `question_controller_test.dart`. (Tests must end in `_test.dart` and live in the `test` directory for the tools to find them without you having to specify their path.) In this file, import both the `test` and `quiz` package.

```dart
import 'package:test/test.dart';
import 'package:quiz/quiz.dart';
```

The way Aqueduct accomplishes testing is by starting an entire application, running the tests, then stopping the application. To accomplish this, declare a `setUpAll` and `tearDownAll` method to run before and after all tests. After the import statements, add a `main` function with the appropriate setup and teardown code:

```dart
void main() {
  var app = new Application<QuizSink>();

  setUpAll(() async {
    await app.start(runOnMainIsolate: true);
  });

  tearDownAll(() async {
    await app.stop();
  });
}
```

Once we add tests and run this test file, an instance of a `QuizSink` driven `Application` will be started. Because starting an application takes a few milliseconds, we must make sure that we `await` its startup prior to moving on to the tests. Likewise, we may run multiple groups of tests or files with different tests in them, so we have to shut down the application when the tests are finished to free up the port the `Application` is listening on. (You really really shouldn't forget to shut it down, because if you don't, subsequent tests will start to fail because the application can't bind to the listening port.)

Notice also that `start` takes an optional argument, `runOnMainIsolate`. In the previous chapter, we talked about an application spreading across multiple isolates. All of that behavior is tested in Aqueduct, and so your tests should only test the logic of your `QuizSink` and its streams of `RequestController`s. Since isolates can't share memory, if you ever want to dig into your `QuizSink` and check things out or use some of its resources directly, you wouldn't be able to do that from the tests when running across multiple isolates - the test isolate is separate from the running `QuizSink` isolates. Therefore, when running tests, you should set this flag to true. (This flag is specifically meant for tests.)

Now, we need to add a test to verify that hitting the `/questions` endpoint does return our definition of 'questions'. In Aqueduct, there is a utility called a `TestClient` to make this a lot easier. At the top of your main function, but after we create the application instance, declare a new variable:

```dart
void main() {
  var app = new Application<QuizSink>();
  var client = new TestClient(app.configuration.port);
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

If you run this test file now, an instance of your application will spin up on the main isolate, and your first test will execute a GET `http://localhost:8080/questions`, then your application will be torn down. Of course, we don't verify anything about the response, so we should actually do something there.

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

Now, make sure you shut down your application if you were running it from a previous chapter. To run a test file in Atom, you can do two things: manually hit Cmd-Shift-P and type in run test or use the keyboard shortcut, Cmd-Option-Ctrl-T. The test results will appear in a panel. (Make sure you save your test file first! Oh, and you can also run the tests just by running the test file in the same way you ran the `quiz.dart` file. Atom currently isn't great at displaying test results. A more powerful option is IntelliJ IDEA Community Edition, but Atom is a lot friendlier for a tutorial.)

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
