# 2. Writing Tests

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

Tests are made possible by the `test` package which you'll need to claim as a dependency. Locate the file `quiz/pubspec.yaml` in your project. This file contains metadata about your application, including it's dependencies. At the bottom of this file, the following two lines specify that this project uses the `test` package as a development dependency:

```
dev_dependencies:
  test: any
```

In Dart, tests are stored in a top-level `test` directory that has already been created from the template. Add a new file to it named `test/question_controller_test.dart`. (Tests must end in `_test.dart` and live in the `test` directory.) In this file, import your application's test harness:

```dart
import 'harness/app.dart';
```

The test harness exports the `test` package and declares a class named `TestApplication`. Aqueduct's testing strategy is simple: run the application locally, execute requests and verify their responses. A `TestApplication` can run the application from your tests and has a `client` property for executing requests against that application. In `test/question_controller_test.dart`, add the following code to set up the test harness:

```dart
Future main() async {
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
void main() {
  ...

  test("/questions returns list of questions", () async {
    var request = app.client.request("/questions");
    expectResponse(
      await request.get(),
      200,
      body: everyElement(endsWith("?")));
  });
}
```

This test executes the request `GET http://localhost/questions` and ensures that the response's status code is 200 and the body is a list of strings that all end in '?'.

The method `expectResponse` takes a `TestResponse`, status code and an optional *body matcher* (it optionally takes a header matcher, too). It verifies that the response has the expected values and fails the test if it doesn't.

A `TestResponse` is created by executing a `TestRequest`, which is created by with the `request` method of a `TestApplication`'s `client`. The execution methods for `TestRequest` are `get()`, `post()`, etc.

Run this test by right-clicking anywhere on it and selecting `Run` from the pop-up menu. A test runner will appear on the bottom of the screen with the results of the test.

There's one little issue here: the `everyElement` matcher ensures each string in the response body passes the inner matcher `endsWith`. However, if the response body were an empty list, the inner matcher would never run and the test would still pass. Let's verify that there is at least one question, too:

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

## [Next Chapter: Executing Database Queries](executing-queries.md)
