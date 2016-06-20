---
layout: page
title: "Writing Tests"
category: tut
date: 2016-06-20 09:38:12
order: 2
---

This chapter expands on the previous (link).

In general, testing in Dart is simple: you write a `main` function and use the `test` function register a test. Each test is a closure that runs some code and has expectations. For example, this code would test that 1 + 1 = 2:

```
import 'package:test/test.dart';

void main() {
  test("1+1 = 2", () {
    expect(1 + 1, equals(2));
  });
}
```

Tests are made possible by the `test` package. If you take a look at the `pubspec.yaml` file in the `quiz` project from last chapter, you'll see that it already a dependency of your project:

```
dev_dependencies:
  test: '>=0.12.0 <0.13.0'
```

One of the core principles of `aqueduct` is efficient testing. While opening up your browser and typing in a URL can verify the code you just wrote succeeds, it's not a very reliable way of testing software. We'll also run into some dead-ends when we test HTTP requests that use an HTTP method other than GET. Therefore, there are some helpful utilities for writing tests built into `aqueduct` and the `wildfire` template.

Let's write some tests for ensure that the `/questions` endpoint behaves as expected.

In the `quiz` project, create a new test file by right-clicking on the top-level `test` directory and selecting 'New' -> 'Dart File'. Name this file `question_controller_test`. (It's important that test file names end with `_test` and that they are in the `test` directory for the tooling to recognize them.)

 At the top of `question_controller_test.dart`, import the `test` package and your application's package so that the tests can see them:

```
import 'package:test/test.dart';
import 'package:quiz/quiz.dart';
```

The way `aqueduct` accomplishes testing is by starting an entire application, running the tests, then stopping the application. The `wildfire` template includes a Dart file `test/mock/startup.dart` for this purpose.
