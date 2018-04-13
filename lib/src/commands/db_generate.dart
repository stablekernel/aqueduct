import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/commands/scripts/migration_builder.dart';
import 'package:isolate_executor/isolate_executor.dart';

import '../db/db.dart';
import 'base.dart';
import 'db.dart';

class CLIDatabaseGenerate extends CLIDatabaseManagingCommand {
  @override
  Future<int> handle() async {
    var existingMigrations = projectMigrations;

    var newMigrationFile = new File.fromUri(migrationDirectory.uri.resolve("00000001_Initial.migration.dart"));
    var versionNumber = 1;

    if (existingMigrations.isNotEmpty) {
      versionNumber = existingMigrations.last.versionNumber + 1;
      newMigrationFile = new File.fromUri(
          migrationDirectory.uri.resolve("${"$versionNumber".padLeft(8, "0")}_Unnamed.migration.dart"));
    }

    final schema = await schemaByApplyingMigrationSources(projectMigrations);
    var result = await generateMigrationSource(schema, versionNumber);

    displayInfo("The following ManagedObject<T> subclasses were found:");
    result.tablesEvaluated.forEach((t) => displayProgress(t));
    displayProgress("");
    displayProgress(
        "* If you were expecting more declarations, ensure the files are visible in the application library file.");
    displayProgress("");

    result.changeList?.forEach((c) => displayProgress(c));

    newMigrationFile.writeAsStringSync(result.source);

    displayInfo("Created new migration file (version ${versionNumber}).", color: CLIColor.boldGreen);
    displayProgress("New file is located at ${newMigrationFile.path}");

    return 0;
  }

  Future<MigrationBuilderResult> generateMigrationSource(Schema initialSchema, int inputVersion) async {
    final resultMap = await IsolateExecutor.executeWithType(MigrationBuilderExecutable,
        packageConfigURI: packageConfigUri,
        imports: MigrationBuilderExecutable.importsForPackage(packageName),
        message: MigrationBuilderExecutable.createMessage(inputVersion, initialSchema), logHandler: displayProgress);

    return new MigrationBuilderResult.fromMap(resultMap);
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
