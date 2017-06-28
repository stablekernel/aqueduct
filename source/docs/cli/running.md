# Running Applications with Aqueduct Serve

The `aqueduct serve` command-line tool runs applications. This tool is run in a project directory and it generates a Dart script that bootstraps your application.

The structure of the project does matter - if you are creating a project from the template, the appropriate structure already exists. Otherwise, you must ensure you have a library file with the same name as your application (as defined in `pubspec.yaml`). For example, in application named `todo` must have a `lib/todo.dart` file. This file must import the file that declares your application's `RequestSink`.


You may specify options like the number of isolates to run the application on and which port to listen for requests on. See more details with `aqueduct serve --help`.
