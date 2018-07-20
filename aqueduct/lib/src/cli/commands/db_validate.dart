import 'dart:async';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/mixins/database_managing.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/scripts/get_schema.dart';
import 'package:aqueduct/src/db/schema/schema.dart';
import 'package:isolate_executor/isolate_executor.dart';

class CLIDatabaseValidate extends CLICommand
    with CLIDatabaseManagingCommand, CLIProject {
  @override
  Future<int> handle() async {
    var migrations = projectMigrations;
    if (migrations.isEmpty) {
      displayError("No migration files found in ${migrationDirectory.path}.");
      return 1;
    }

    final currentSchema = Schema.fromMap(await IsolateExecutor.run(
        GetSchemaExecutable({}),
        imports: GetSchemaExecutable.importsForPackage(libraryName),
        packageConfigURI: packageConfigUri,
        logHandler: displayProgress));
    var schemaFromMigrationFiles =
        await schemaByApplyingMigrationSources(migrations);

    var differences = currentSchema.differenceFrom(schemaFromMigrationFiles);

    if (differences.hasDifferences) {
      displayError("Validation failed");
      differences.errorMessages.forEach(displayProgress);

      return 1;
    }

    displayInfo("Validation OK", color: CLIColor.boldGreen);
    displayProgress("Latest version is ${migrations.last.versionNumber}.");

    return 0;
  }

  @override
  String get name {
    return "validate";
  }

  @override
  String get description {
    return "Compares the schema created by the sum of migration files to the current codebase's schema.";
  }
}
