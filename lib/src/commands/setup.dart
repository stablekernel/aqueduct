import 'dart:async';
import 'dart:io';

import 'base.dart';

class CLISetup extends CLICommand {
  CLISetup() {
    options
      ..addOption("granting-user",
          abbr: "u",
          defaultsTo: "postgres",
          help:
              "The username of the PostgreSQL user that has privileges to create a new test user and test database.")
      ..addFlag("confirm",
          abbr: "c",
          negatable: false,
          help: "Confirms that you wish to carry out this setup.");
  }

  bool get confirm => values["confirm"];
  String get grantingUser => values["granting-user"];

  Future<int> handle() async {
    if (!(await hasPSQLCLI)) {
      displayError(
          "No psql found in PATH.\n\nIf you do not have PostgreSQL installed locally, "
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

      var result = await Process.runSync("psql", args, runInShell: true);
      if (result.stdout.contains("CREATE DATABASE")) {
        displayProgress("Successfully created database dart_test.");
      } else if (result.stdout.contains("CREATE ROLE")) {
        displayProgress(
            "Successfully created role 'dart' with createdb permissions.");
      } else if (result.stdout.contains("ALTER ROLE")) {
        displayProgress("Successfully set user 'dart' password to 'dart'.");
      } else if (result.stdout.contains("GRANT")) {
        displayProgress(
            "Successfully granted all privileges to database dart_test to user 'dart'.");
      }

      if (result.stderr.contains("database \"dart_test\" already exists")) {
        displayProgress("Database dart_test already exists, continuing.");
      } else if (result.stderr.contains("role \"dart\" already exists")) {
        displayProgress("User 'dart' already exists, continuing.");
      } else if (result.stderr.contains("could not connect to server")) {
        displayError(
            "Database is not accepting connections. Ensure that PostgreSQL is running locally.");

        return -1;
      } else if (result.stderr.length > 0) {
        displayError("Unknown error: ${result.stderr}");
        return -1;
      }
    }

    displayInfo(
        "Congratulations! Aqueduct applications can now be tested locally.");

    return 0;
  }

  Future<bool> get hasPSQLCLI async {
    String locator = Platform.isWindows ? "where" : "which";
    ProcessResult results =
        Process.runSync(locator, ["psql"], runInShell: true);

    return results.exitCode == 0;
  }

  String get name {
    return "setup";
  }

  String get description {
    return "A one-time setup command for your development environment.";
  }
}
