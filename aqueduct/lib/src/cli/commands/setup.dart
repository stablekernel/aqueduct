import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';

class CLISetup extends CLICommand with CLIProject {
  bool get shouldSetupHeroku => herokuName != null;

  @Option("heroku",
      help:
          "Sets up the project in the current directory for deplying to Heroku.",
      valueHelp: "The name of the Heroku application.")
  String get herokuName => decode("heroku");

  @Flag("tests",
      help:
          "Sets up a local database to run application tests. If no other option is on, the command defaults to this flag.")
  bool get shouldSetupTests => decode("tests");

  @Flag("confirm",
      abbr: "c",
      negatable: false,
      help: "Confirms that you wish to carry out this setup.")
  bool get confirm => decode("confirm");

  @Option("granting-user",
      abbr: "u",
      defaultsTo: "postgres",
      help:
          "The username of the PostgreSQL user that has privileges to create a new test user and test database.")
  String get grantingUser => decode("granting-user");

  @override
  Future<int> handle() async {
    if (shouldSetupHeroku) {
      return setupHerokuProject();
    } else /*if (shouldSetupTests*/ {
      return setupTestEnvironment();
    }
  }

  bool get hasGitCLI => isExecutableInShellPath("git");
  bool get hasPSQLCLI => isExecutableInShellPath("psql");
  bool get hasHerokuCLI => isExecutableInShellPath("heroku");

  Future<int> setupHerokuProject() async {
    if (!hasHerokuCLI) {
      displayError("The application 'heroku' was not found in \$PATH.");
      displayProgress(
          "Install 'heroku' from https://devcenter.heroku.com/articles/heroku-cli.");
      return -1;
    }

    if (!hasGitCLI) {
      displayError("The application 'git' was not found in \$PATH.");
      displayProgress("Install 'git' from https://git-scm.com/downloads.");
    }

    displayInfo("Setting up Heroku for $herokuName");

    var commands = [
      ["git:remote", "-a", herokuName],
      [
        "config:set",
        "DART_SDK_URL=https://storage.googleapis.com/dart-archive/channels/stable/release/latest/sdk/dartsdk-linux-x64-release.zip"
      ],
      [
        "config:add",
        "BUILDPACK_URL=https://github.com/stablekernel/heroku-buildpack-dart.git"
      ],
      [
        "config:set",
        "PATH=/app/bin:/usr/local/bin:/usr/bin:/bin:/app/.pub-cache/bin:/app/dart-sdk/bin"
      ],
      ["config:set", "PUB_CACHE=/app/pub-cache"],
    ];

    for (var cmd in commands) {
      displayProgress(
          "Running heroku ${cmd.join(" ")} in ${projectDirectory.path}");
      var result = await Process.run("heroku", cmd,
          workingDirectory: projectDirectory.path);
      if (result.exitCode != 0) {
        throw CLIException("Heroku command failed",
            instructions: ["${result.stdout} ${result.stderr}"]);
      }
    }

    displayProgress("Removing config.yaml from .gitignore");
    var gitIgnore = fileInProjectDirectory(".gitignore");
    var contents =
        gitIgnore.readAsStringSync().replaceAll(RegExp("config.yaml\\n"), "");
    gitIgnore.writeAsStringSync(contents);

    var procFile = fileInProjectDirectory("Procfile");
    procFile.writeAsStringSync("""
release: /app/dart-sdk/bin/pub global run aqueduct:aqueduct db upgrade --connect \$DATABASE_URL
web: /app/dart-sdk/bin/pub global run aqueduct:aqueduct serve --port \$PORT --no-monitor
    """);

    return 0;
  }

  Future<int> setupTestEnvironment() async {
    if (!hasPSQLCLI) {
      displayError(
          "The application 'psql' was not found in \$PATH.\n\nIf you do not have PostgreSQL installed locally, "
          "you must do so to run tests in an Aqueduct application. For macOS users, "
          "download Postgres.app from http://postgresapp.com. Once installed, open the "
          "application at least once and add the following line to ~/.bash_profile:\n\n"
          "\texport PATH=\$PATH:/Applications/Postgres.app/Contents/Versions/latest/bin\n\n"
          "You may have to reload the shell you ran this command from after installation. "
          "For non-macOS users, you must install a local version of PostgreSQL"
          "and ensure the command line executable 'psql' is in your PATH.");

      return -1;
    }

    var commands = [
      "create database dart_test;",
      "create user dart with createdb;",
      "alter user dart with password 'dart';",
      "grant all on database dart_test to dart;"
    ];

    if (!confirm) {
      displayInfo("Confirmation Needed");
      displayProgress(
          "This command will execute SQL to create a test database.");
      displayProgress(
          "As a security measure, you must add --confirm (or -c) to this command.");
      displayProgress("The commands that will be run upon confirmation:");
      commands.forEach((cmd) {
        displayProgress("\t* psql -c '$cmd' -U $grantingUser");
      });
      return -1;
    }

    displayInfo("Connecting to database...");
    for (var cmd in commands) {
      List<String> args = ["-c", cmd, "-U", grantingUser];

      final result = Process.runSync("psql", args, runInShell: true);
      final output = (result.stdout as String) + (result.stderr as String);
      if (output.contains("CREATE DATABASE")) {
        displayProgress("Successfully created database dart_test.");
      } else if (output.contains("CREATE ROLE")) {
        displayProgress(
            "Successfully created role 'dart' with createdb permissions.");
      } else if (output.contains("ALTER ROLE")) {
        displayProgress("Successfully set user 'dart' password to 'dart'.");
      } else if (output.contains("GRANT")) {
        displayProgress(
            "Successfully granted all privileges to database dart_test to user 'dart'.");
      }

      if (output.contains("database \"dart_test\" already exists")) {
        displayProgress("Database dart_test already exists, continuing.");
      } else if (output.contains("role \"dart\" already exists")) {
        displayProgress("User 'dart' already exists, continuing.");
      } else if (output.contains("could not connect to server")) {
        displayError(
            "Database is not accepting connections. Ensure that PostgreSQL is running locally.");

        return -1;
      } else if ((result.stderr as String).isNotEmpty) {
        displayError("Unknown error: ${result.stderr}");
        return -1;
      }
    }

    displayInfo(
        "Congratulations! Aqueduct applications can now be tested locally.");

    return 0;
  }

  @override
  String get name {
    return "setup";
  }

  @override
  String get description {
    return "A one-time setup command for your development environment.";
  }
}
