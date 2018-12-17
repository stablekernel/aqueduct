# Running Applications with Aqueduct Serve

The `aqueduct serve` command-line tool runs applications. This tool is run in a project directory and it generates a Dart script that bootstraps your application.

The structure of the project does matter - if you are creating a project from the template, the appropriate structure already exists. Otherwise, you must ensure you have a library file with the same name as your application (as defined in `pubspec.yaml`). For example, an application named `todo` must have a `lib/todo.dart` file. This file must import the file that declares your application's `ApplicationChannel`.

You may specify options like the number of isolates to run the application on and which port to listen for requests on. See more details with `aqueduct serve --help`.

## Hot Reload

In Flutter, a *hot reload* restarts an application after a code change, but keeps the state of the application intact - such as which screen the user is on and what data is available in memory. This is an incredible feature for faster development cycles in an environment that can often be difficult to test efficiently.

Hot reload is often requested as a feature of Aqueduct, but it doesn't quite make sense in an HTTP API which is not supposed to retain state. Truth be told, our team rarely uses a development cycle that involves making frequent code changes to a locally running instance. Instead, we use `package:aqueduct_test` to ensure all of our testing efforts are captured in automated tests that continually run over the course of the project.

A shortcut to restart the locally running application after a change is admittedly useful in some scenarios. However, this is already an existing feature of most IDEs and should not be implemented by `aqueduct`. In IntelliJ, this feature is called 'Rerun' and the default keyboard shortcut is `^F5` in macOS. To use this shortcut, instead of running with `aqueduct serve`, right-click on the `bin/main.dart` script that is generated when you create a new project and select `Run`. Once this process is running, you can rerun it with `^F5` or with the Rerun button on the Run panel.
