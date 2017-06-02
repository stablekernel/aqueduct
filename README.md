![Aqueduct](https://raw.githubusercontent.com/stablekernel/aqueduct/master/images/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

[![Gitter](https://badges.gitter.im/dart-lang/server.svg)](https://gitter.im/dart-lang/server?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Aqueduct is a server-side framework for building and deploying REST applications. It is written in Dart. Its goal is to provide an integrated, consistently styled API.

The framework contains behavior for routing and authorizing HTTP requests, persisting data in PostgreSQL, testing, and more. 

The `aqueduct` command-line tool serves applications, manages database schemas and OAuth 2.0 clients, and generates OpenAPI specifications.

Aqueduct is well-tested, documented and adheres to semantic versioning.

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Create a new project.

        aqueduct create my_project

Open the project directory in an [IntelliJ IDE](https://www.jetbrains.com/idea/download/), [Atom](https://atom.io) or [Visual Studio Code](https://code.visualstudio.com). All three IDEs have a Dart plugin.

## Tutorials and Documentation

Step-by-step tutorials for beginners are available [here](https://aqueduct.io/docs/tut/getting-started).

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest) or you can install it in [Dash](https://kapeli.com/docsets#dartdoc).

You can find in-depth and conceptual guides [here](https://aqueduct.io/docs/).

## An Example

The only requirement of an Aqueduct application is that it contains a single [RequestSink](https://aqueduct.io/docs/http/request_sink/) subclass. The example application below exposes `POST /notes`, `GET /notes`, `GET /notes/:id`, `PUT /notes/:id` and `DELETE /notes/:id` and stores data in a PostgreSQL database.

```dart
import 'package:aqueduct/aqueduct.dart';

class AppRequestSink extends RequestSink {
  AppRequestSink(ApplicationConfiguration config) : super(config) {
    logger.onRecord.listen((p) => print("$p"));

    var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
    var psc = new PostgreSQLPersistentStore.fromConnectionInfo(
        "dart", "dart", "localhost", 5432, "dart_test");

    ManagedContext.defaultContext = new ManagedContext(dataModel, psc);
  }

  @override
  void setupRouter(Router router) {
    router
      .route("/notes[/:id]")
      .generate(() => new ManagedObjectController<Note>());
  }
}

class Note extends ManagedObject<_Note> implements _Note {}
class _Note {
  @managedPrimaryKey
  int id;

  String contents;
}
```
