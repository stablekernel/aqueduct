part of aqueduct;

class CLISetup extends CLICommand {
  ArgParser options = new ArgParser(allowTrailingOptions: false)
    ..addOption("granting-user", abbr: "u", defaultsTo: "postgres", help: "The username of the PostgreSQL user that can create new users and databases.")
    ..addFlag("confirm", abbr: "c", negatable: false, help: "Confirms that you wish to carry out this setup.")
    ..addFlag("help", abbr: "h", negatable: false, help: "Shows this documentation");

  Future<int> handle(ArgResults argValues) async {
    if (argValues["help"] == true) {
      print("${options.usage}");
      return 0;
    }

    if (!(await hasPSQLCLI)) {
      print("No psql found in PATH.\n\nIf you do not have PostgreSQL installed locally, you must do so to run tests in an Aqueduct application. For macOS users, "
        "download Postgres.app from http://postgresapp.com. Once installed, open the application at least once and add the following line to ~/.bash_profile:\n\n"
        "\texport PATH=\$PATH:/Applications/Postgres.app/Contents/Versions/latest/bin\n\n"
        "You may have to reload the shell you ran this command from after installation. For non-macOS users, you must install a local version of PostgreSQL"
        "and ensure the command line executable 'psql' is in your PATH.");

      return -1;
    }

    var username = argValues["granting-user"];
    var commands = [
      "create database dart_test;",
      "create user dart with createdb;",
      "alter user dart with password 'dart';",
      "grant all on database dart_test to dart;"
    ];

    if (argValues["confirm"] != true) {
      print("This command will execute commands with the 'psql' application in your PATH to create a new user and database used for testing. "
        "As a security measure, you must add --confirm (or -c) to this command line tool to ensure this script doesn't do something you don't want it to do. "
        "The script will run the following commands:\n\n");
      commands.forEach((cmd) {
        print("\tpsql -c '$cmd' -U $username");
      });
      return -1;
    }

    for (var cmd in commands) {
      var result = await Process.runSync("psql", ["-c", cmd], runInShell: true);
      if (result.stdout.contains("CREATE DATABASE")) {
        print("Successfully created database dart_test.");
      } else if (result.stdout.contains("CREATE ROLE")) {
        print("Successfully created role 'dart' with createdb permissions.");
      } else if (result.stdout.contains("ALTER ROLE")) {
        print("Successfully set user 'dart' password to 'dart'.");
      } else if (result.stdout.contains("GRANT")) {
        print("Successfully granted all privileges to database dart_test to user 'dart'.");
      }

      if (result.stderr.contains("database \"dart_test\" already exists")) {
        print("Database dart_test already exists, continuing.");
      } else if (result.stderr.contains("role \"dart\" already exists")) {
        print("User 'dart' already exists, continuing.");
      } else if (result.stderr.contains("could not connect to server")) {
        print("Database is not accepting connections. Ensure that PostgreSQL is running locally.");
        return -1;
      } else if (result.stderr.length > 0) {
        print("Unknown error: ${result.stderr}");
        return -1;
      }
    }

    print("Congratulations! Aqueduct applications can now be tested locally.");

    return 0;
  }

  Future<bool> get hasPSQLCLI async {
    var results = Process.runSync("which", ["psql"], runInShell: true);

    String out = results.stdout;
    if (out.startsWith("/")) {
      return true;
    }
    return false;
  }
}