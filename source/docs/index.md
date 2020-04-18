![Aqueduct](https://s3.amazonaws.com/aqueduct-collateral/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

<a href="http://slackaqueductsignup.herokuapp.com/"><img src="https://slackaqueductsignup.herokuapp.com/badge.svg" alt="Slack"/></a><br/>

## Aqueduct

Aqueduct is an HTTP web server framework for building REST applications written in Dart.

## How to Use this Documentation

The menu on the left contains a hierarchy documents. Those documents - and how you should use them - are described in the following table:

| Location | Description | Recommended Usage |
|---|---|---|
| Top-Level (e.g. Tour, Core Concepts) | Introductory and quick reference documents | Read these documents when you are new to Aqueduct |
| Snippets | Example code snippets of common behaviors | Read these documents for examples and inspiration
| Tutorial | A linear, guided tutorial to building your first application | A 1-3 hour long tutorial to learn Aqueduct |
| Guides | A hierarchy of in-depth guides for the many facets of Aqueduct | Refer to these documents often to understand concepts and usage of Aqueduct |

In addition to these guides, be sure to use the [API Reference](https://pub.dev/documentation/aqueduct/latest/) to look up classes, methods, functions and other elements of the framework.

## Getting Started Tips

The best way to get started is to read the [Core Concepts guide](core_concepts.md) while working through the [tutorial](tut/getting-started.md). Then, add new features to the application created during the tutorial by looking up the classes you are using in the [API Reference](https://pub.dev/documentation/aqueduct/latest/), and implementing behavior not found in the tutorial. 

Once you have the basic concepts down, start reading the guides in the left hand menu to take advantage of the many features of the framework. Check out the repository of examples [here](https://github.com/stablekernel/aqueduct_examples).

Import [this file](https://s3.amazonaws.com/aqueduct-intellij/aqueduct.jar) into IntelliJ IDEA for Aqueduct file and code templates.

Aqueduct is catered towards test-driven development - the best way to write an application is to write tests using a [test harness](testing/tests.md) and run those tests after implementing an endpoint. You may also run the command `aqueduct document client` in your project directory to generate a web client for your application. This client can be opened in any browser and will execute requests against your locally running application.
