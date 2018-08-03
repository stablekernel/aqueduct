import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/scripts/migration_builder.dart';
import 'package:aqueduct/src/db/schema/schema.dart';
import 'package:isolate_executor/isolate_executor.dart';

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
    var result = await generateMigrationSource(schema, versionNumber);

    displayInfo("The following ManagedObject<T> subclasses were found:");
    result.tablesEvaluated.forEach(displayProgress);
    displayProgress("");
    displayProgress(
        "* If you were expecting more declarations, ensure the files are visible in the application library file.");
    displayProgress("");

    result.changeList?.forEach(displayProgress);

    if (result.source.contains("<<set>>")) {
      displayInfo("File requires input.");
      displayProgress(
          "This migration file requires extra configuration. This is likely because "
          "a non-nullable column was added to your schema, and needs a default value. "
          "Search for <<set>> in the migration file and replace it with a valid value. "
          "(Note that text columns require a single-quoted string, e.g. \"'default'\".)");
    }
    newMigrationFile.writeAsStringSync(result.source);

    displayInfo("Created new migration file (version $versionNumber).",
        color: CLIColor.boldGreen);
    displayProgress("New file is located at ${newMigrationFile.path}");

    return 0;
  }

  Future<MigrationBuilderResult> generateMigrationSource(
      Schema initialSchema, int inputVersion) async {
    final resultMap = await IsolateExecutor.run(
        MigrationBuilderExecutable.input(initialSchema, inputVersion),
        packageConfigURI: packageConfigUri,
        imports: MigrationBuilderExecutable.importsForPackage(packageName),
        logHandler: displayProgress);

    return MigrationBuilderResult.fromMap(resultMap);
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
