import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/scripts/migration_builder.dart';

class CLIDatabaseGenerate extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject {
  @override
  Future<int> handle() async {
    var existingMigrations = projectMigrations;

    var newMigrationFile = File.fromUri(
        migrationDirectory.uri.resolve("00000001_initial.migration.dart"));
    var versionNumber = 1;

    if (existingMigrations.isNotEmpty) {
      versionNumber = existingMigrations.last.versionNumber + 1;
      newMigrationFile = File.fromUri(migrationDirectory.uri.resolve(
          "${"$versionNumber".padLeft(8, "0")}_unnamed.migration.dart"));
    }

    final schema = await schemaByApplyingMigrationSources(projectMigrations);
    final result = await generateMigrationFileForProject(this, schema, versionNumber);

    displayInfo("The following ManagedObject<T> subclasses were found:");
    displayProgress("${result.tablesEvaluated.join(", ")}");
    displayProgress("");
    displayProgress(
        "* If you were expecting more declarations, ensure the files are visible in the application library file.");
    displayProgress("");

    result.changeList?.forEach(displayProgress);



    newMigrationFile.writeAsStringSync(result.source);

    displayInfo("Created new migration file (version $versionNumber).",
        color: CLIColor.boldGreen);
    displayProgress("New file is located at ${newMigrationFile.path}");

    return 0;
  }

  @override
  String get name {
    return "generate";
  }

  @override
  String get detailedDescription {
    return "The migration file will upgrade the schema generated from running existing migration files match that of the schema in the current codebase.";
  }

  @override
  String get description {
    return "Creates a migration file.";
  }
}
