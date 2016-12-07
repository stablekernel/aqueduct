![Aqueduct](https://raw.githubusercontent.com/stablekernel/aqueduct/master/images/aqueduct.png)

[![Build Status](https://travis-ci.org/stablekernel/aqueduct.svg?branch=master)](https://travis-ci.org/stablekernel/aqueduct) [![codecov](https://codecov.io/gh/stablekernel/aqueduct/branch/master/graph/badge.svg)](https://codecov.io/gh/stablekernel/aqueduct)

Aqueduct is a server-side framework written in Dart.

## Getting Started

1. [Install Dart](https://www.dartlang.org/install).
2. Activate Aqueduct

        pub global activate aqueduct

3. Run first time setup.

        aqueduct setup

4. Create a new project.

        aqueduct create -n my_project

Open the project directory in the editor of your choice. Our preferred editor is [IntellIJ IDEA Community Edition](https://www.jetbrains.com/idea/download/) (with the [Dart Plugin](https://plugins.jetbrains.com/plugin/6351)). [Atom](https://atom.io) is also a good editor, but support for running Dart tests is lacking.

## Major Features

1. HTTP Request Routing and Middleware          
2. Multiple CPU support, without adding complicated multi-threading logic.
3. CORS Support.
4. Automatic OpenAPI specification/documentation generation.
5. OAuth 2.0 implementation.
6. Fully-featured ORM, with clear, type- and name-safe syntax, and SQL Join support. (Supports PostgreSQL by default.)          
7. Database migration tooling.
8. Template projects for quick starts.
9. Integration with CI tools. (Supports TravisCI by default.)        
10. Integrated testing utilities for clean and productive tests.
11. Logging to Rotating Files or Console

## Tutorials

Need a walkthrough? Read the [tutorials](http://stablekernel.github.io/aqueduct/). They take you through the steps of building an Aqueduct application.

## Documentation

You can find the API reference [here](https://www.dartdocs.org/documentation/aqueduct/latest).
You can find in-depth guides and tutorials [here](http://stablekernel.github.io/aqueduct/).

## Roadmap

[Here's where we are headed.](ROADMAP.md)

## An Example

The following is a complete application, with endpoints to create, get, update and delete 'Notes' that are stored in a PostgreSQL database.

```dart
import 'package:aqueduct/aqueduct.dart';

void main() {
  var app = new Application<AppRequestSink>();
  app.start(numberOfInstances: 3);
}

class AppRequestSink extends RequestSink {
  AppRequestSink(Map<String, dynamic> opts) : super(opts) {
    logger.onRecord.listen((p) => print("$p"));

    var dataModel =
        new ManagedDataModel.fromPackageContainingType(this.runtimeType);
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

Want to try this out? Save this code in a file named `main.dart`. In the same directory, create a `pubspec.yaml` file with the following contents:

```yaml
name: app

dependencies:
  aqueduct: any
```
Connect to `postgres://dart:dart@localhost:5432/dart_test` and create a table (with this exact name) just like this:

```sql
create table _note (id bigserial primary key, contents text);
```

Now, run it:

```sh
pub get
dart main.dart
```

And now you can make requests:

```sh
# Create a new note: POST /notes
curl -X POST http://localhost:8080/notes -H "Content-Type: application/json" -d '{"contents" : "a note"}'

# Get that note: GET /notes/1
curl -X GET http://localhost:8080/notes/1

# Change that note: PUT /notes/1
curl -X PUT http://localhost:8080/notes/1 -H "Content-Type: application/json" -d '{"contents" : "edit"}'

# Delete that note: 
curl -X DELETE http://localhost:8080/notes/1

# Note there are no more notes:
curl -X GET http://localhost:8080/notes
```
