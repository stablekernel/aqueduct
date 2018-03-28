import 'dart:async';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';

class CLIDatabaseValidate extends CLIDatabaseManagingCommand {
  @override
  Future<int> handle() async {
    var files = migrationFiles;
    if (files.isEmpty) {
      displayError("No migration files found in ${migrationDirectory.path}.");
      return 1;
    }

    var currentSchemaGenerator = new SourceGenerator((List<String> args, Map<String, dynamic> values) async {
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);

      return schema.asMap();
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var currentSchemaExecutor = new IsolateExecutor(currentSchemaGenerator, [libraryName],
        packageConfigURI: projectDirectory.uri.resolve(".packages"));
    var result = await currentSchemaExecutor.execute();
    var currentSchema = new Schema.fromMap(result as Map<String, dynamic>);

    var schemaFromMigrationFiles = new Schema.empty();
    for (var migrationFile in migrationFiles) {
      schemaFromMigrationFiles = await schemaByApplyingMigrationFile(migrationFile, schemaFromMigrationFiles);
    }

    var differences = currentSchema.differenceFrom(schemaFromMigrationFiles);

    if (differences.hasDifferences) {
      displayError("Validation failed");
      differences.errorMessages.forEach((diff) {
        displayProgress(diff);
      });

      return 1;
    }

    displayInfo("Validation OK", color: CLIColor.boldGreen);
    displayProgress("Latest version is ${versionNumberFromFile(migrationFiles.last)}");

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
