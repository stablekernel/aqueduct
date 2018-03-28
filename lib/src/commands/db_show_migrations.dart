import 'dart:async';

import 'base.dart';
import 'db.dart';

class CLIDatabaseShowMigrations extends CLIDatabaseManagingCommand {
  @override
  Future<int> handle() async {
    var files = migrationFiles.map((f) {
      var versionString = "${versionNumberFromFile(f)}".padLeft(8, "0");
      return " $versionString | ${f.uri.pathSegments.last}";
    }).join("\n");

    print(" Version  | Path");
    print("----------|-----------");
    print("$files");

    return 0;
  }

  @override
  String get name {
    return "list";
  }

  @override
  String get description {
    return "Show the path and version all migration files for this project.";
  }
}
