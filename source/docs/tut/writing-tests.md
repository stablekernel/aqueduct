# 4. Writing Tests

One of the core principles of Aqueduct is effective testing. While opening up your browser and typing in a URL can verify the code you just wrote succeeds, it's not a very reliable way of testing software. We'll also run into trouble when testing endpoints that use HTTP methods other than GET. Therefore, there are some helpful utilities for writing tests in Aqueduct.

Testing in Dart is simple: create a file that ends with `_test.dart`, write a `main` function and use the `test` function register a test. Each test is a closure that runs some code and has expectations. For example, this code would test that 1 + 1 = 2:

```dart
import 'package:test/test.dart';

void main() {
  test("1+1 = 2", () {
    expect(1 + 1, equals(2));
  });
}
```

Tests are made possible by the `test` package. The `quiz` application already claims `test` as a dependency, which you can verify by looking at the `pubspec.yaml` in your project directory. At the bottom of this file, the following two lines specify that this project uses the `test` package as a development dependency:

```
dev_dependencies:
  test: any
```

In Dart, tests must be in the `test` directory of the project directory. Add a new file to this directory named `question_controller_test.dart`. In this file, import your application's test harness:

```dart
import 'harness/app.dart';
```

The test harness includes all of the packages you need to test an Aqueduct application and a class named `TestApplication`. A `TestApplication` runs your application by starting an HTTP server, creating an instance of `QuizChannel` and then sending every HTTP request to your channel's entry point. When your tests finish, `TestApplication` will stop the HTTP server.

In `test/question_controller_test.dart`, add the following code to set up the test harness:

```dart
import 'harness/app.dart';

void main() {
  TestApplication app = new TestApplication();

  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });  
}
```

!!! warning ""
    It's really important that the application is stopped in `tearDownAll`, otherwise your tests won't exit because there is an HTTP server running!

Let's add a test to verify that `GET /questions` returns a list of questions in a 200 OK response.

```dart
import 'harness/app.dart';

void main() {
  TestApplication app = new TestApplication();

  setUpAll(() async {
    await app.start();
  });

  tearDownAll(() async {
    await app.stop();
  });  

  test("/questions returns list of questions", () async {
    var request = app.client.request("/questions");
    expectResponse(
      await request.get(),
      200,
      body: everyElement(endsWith("?")));
  });
}
```

This test executes the request `GET http://localhost/questions`. The HTTP server running in your `TestApplication` receives it, and you get a response. The method `expectResponse` verifies that it is the correct response - in this case, when the status code is 200 and the body is a list of strings that all end in '?'.

Run this test by right-clicking anywhere on it and selecting `Run` from the pop-up menu. A test runner will appear on the bottom of the screen with the results of the test.

There's one little issue here: the `everyElement` matcher ensures each string in the response body `endsWith` a question mark. However, if the response body were an empty list, the `endsWith` would never run and the test would still pass - but it isn't the behavior we want. Let's verify that there is at least one question, too:

```dart
test("/questions returns list of questions", () async {
  var request = app.client.request("/questions");
  expectResponse(
    await request.get(),
    200,
    body: allOf([
      hasLength(greaterThan(0)),
      everyElement(endsWith("?"))
    ]));
});
```

## Writing More Tests

Let's write two more tests - first, a test that ensures `GET /questions/:index` returns a single question and then another that ensures an index outside of the range of questions will return a 404. Add the following two tests inside the main function:

```dart
test("/questions/index returns a single question", () async {
  expectResponse(
    await app.client.request("/questions/1").get(),
    200,
    body: endsWith("?"));
});

test("/questions/index out of range returns 404", () async {
  expectResponse(
    await app.client.request("/questions/100").get(),
    404);
  });
```

You can run all of the tests in a test file by right-clicking the `main` function and selecting `Run` from the popup menu.

All of your tests should pass - but what if they don't? If we, for example, went back into `question_controller.dart` and added a new question that didn't end with a `?`:

```dart
var questions = [
  "How much wood can a woodchuck chuck?",
  "What's the tallest mountain in the world?",
  "This is a statement."
];
```

The first test that gets all questions will fail and the following will be printed to the console:

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
            - content-length: 108
            - x-frame-options: SAMEORIGIN
            - content-type: application/json; charset=utf-8
            - x-xss-protection: 1; mode=block
            - x-content-type-options: nosniff
            - server: aqueduct/1
          -------------------------
          >
   Which: the body differs for the following reasons:
          has value 'This is a statement.' which doesn't match a string ending with '?' at index 2
```

The `Expected:` value tells what was expected, the `Actual:` value tells you what you got, and `Which:` tells you why they differ. Here, the body differs because 'This is a statement.' doesn't end with '?'.

Remove `This is a statement.` from the list of questions and your tests will pass again.

## [Next Chapter: Deployment](deploying-and-other-fun-things.md)
