import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';

class CLIDatabaseValidate extends CLICommand
    with CLIDatabaseMigratable, CLIProject {
  Future<int> handle() async {
    var files = migrationFiles;
    if (files.isEmpty) {
      displayError("No migration files found in ${migrationDirectory.path}.");
      return 1;
    }

    var currentSchemaGenerator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
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

    var currentSchemaExecutor = new IsolateExecutor(
        currentSchemaGenerator, [libraryName],
        packageConfigURI: projectDirectory.uri.resolve(".packages"));
    var result = await currentSchemaExecutor.execute(projectDirectory.uri);
    var currentSchema = new Schema.fromMap(result as Map<String, dynamic>);

    var schemaFromMigrationFiles = new Schema.empty();
    for (var migrationFile in migrationFiles) {
      schemaFromMigrationFiles =
          await schemaByApplyingMigrationFile(schemaFromMigrationFiles, migrationFile);
    }

    var differences = currentSchema.differenceFrom(schemaFromMigrationFiles);

    if (!differences.hasDifferences) {
      displayError("Validation failed");
      differences.errorMessages.forEach((diff) {
        displayProgress(diff);
      });

      return 1;
    }

    displayInfo("Validation OK", color: CLIColor.boldGreen);
    displayProgress(
        "Latest version is ${versionNumberFromFile(migrationFiles.last)}");

    return 0;
  }

  Future<Schema> schemaByApplyingMigrationFile(
      Schema baseSchema, File migrationFile) async {
    var sourceFunction =
        (List<String> args, Map<String, dynamic> values) async {
      var inputSchema =
          new Schema.fromMap(values["schema"] as Map<String, dynamic>);

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem()
              .isolate
              .rootLibrary
              .declarations
              .values
              .firstWhere((dm) =>
                  dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration)))
          as ClassMirror;

      var migrationInstance = migrationClassMirror
          .newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(null, inputSchema);

      await migrationInstance.upgrade();

      return migrationInstance.currentSchema.asMap();
    };

    var generator = new SourceGenerator(sourceFunction,
        imports: [
          "dart:async",
          "package:aqueduct/aqueduct.dart",
          "dart:isolate",
          "dart:mirrors"
        ],
        additionalContents: migrationFile.readAsStringSync());

    var schemaMap = await IsolateExecutor.executeSource(generator,
        ["${versionNumberFromFile(migrationFile)}"], projectDirectory.uri,
        message: {"schema": baseSchema.asMap()});

    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }

  String get name {
    return "validate";
  }

  String get description {
    return "Compares the schema created by the sum of migration files to the current codebase's schema.";
  }
}
