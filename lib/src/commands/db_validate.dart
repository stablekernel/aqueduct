import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';

/// Used internally.
class CLIDatabaseValidate extends CLICommand with CLIDatabaseMigratable, CLIProject {
  Future<int> handle() async {
    var files = migrationFiles;
    if (files.isEmpty) {
      displayInfo(
          "Migration directory doesn't contain any migrations, nothing to validate.");
      return 0;
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

    var currentSchemaExecutor = new IsolateExecutor(currentSchemaGenerator, [libraryName],
        packageConfigURI: projectDirectory.uri.resolve(".packages"));
    var currentSchema = new Schema.fromMap(await currentSchemaExecutor.execute(
        workingDirectory: projectDirectory.uri) as Map<String, dynamic>);

    var baseSchema = new Schema.empty();
    for (var migrationFile in migrationFiles) {
      baseSchema = await schemaByApplyingMigrationFile(baseSchema, migrationFile);
    }

    var errors = <String>[];
    var matches = baseSchema.matches(currentSchema, errors);

    if (!matches) {
      displayError(
          "Validation failed:\n\t${errors.join("\n\t")}");
      return 1;
    }

    displayInfo("Validation OK", color: CLIColor.boldGreen);
    displayProgress("Latest version is ${versionNumberFromFile(migrationFiles.last)}");

    return 0;
  }

  Future<Schema> schemaByApplyingMigrationFile(Schema baseSchema, File migrationFile) async {
    var sourceFunction = (List<String> args, Map<String, dynamic> values) async {
      var inputSchema =
      new Schema.fromMap(values["schema"] as Map<String, dynamic>);

      var versionNumber = int.parse(args.first);
      var migrationClassMirror = currentMirrorSystem()
          .isolate
          .rootLibrary
          .declarations
          .values
          .firstWhere((dm) =>
            dm is ClassMirror && dm.isSubclassOf(reflectClass(Migration))) as ClassMirror;

      var migrationInstance = migrationClassMirror
          .newInstance(new Symbol(''), []).reflectee as Migration;
      migrationInstance.database = new SchemaBuilder(null, inputSchema);

      await migrationInstance.upgrade();

      return migrationInstance.currentSchema.asMap();
    };

    var generator = new SourceGenerator(
            sourceFunction, imports: [
              "dart:async",
              "package:aqueduct/aqueduct.dart",
              "dart:isolate",
              "dart:mirrors"
            ],
        additionalContents: migrationFile.readAsStringSync());

    var schemaMap = await IsolateExecutor.executeSource(generator, [
      "${versionNumberFromFile(migrationFile)}"
    ], message: {
      "schema": baseSchema.asMap()
    });

    return new Schema.fromMap(schemaMap as Map<String, dynamic>);
  }

  String get name {
    return "validate";
  }
  String get description {
    return "Compares the schema created by the sum of migration files to the current codebase's schema.";
  }
}