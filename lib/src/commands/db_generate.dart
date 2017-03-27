import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';
import 'db_validate.dart';

class CLIDatabaseGenerate extends CLICommand
    with CLIDatabaseMigratable, CLIProject {
  Future<int> handle() async {
    var files = migrationFiles;

    var newMigrationFile = new File.fromUri(
        migrationDirectory.uri.resolve("00000001_Initial.migration.dart"));
    var versionNumber = 1;

    if (!files.isEmpty) {
      // For now, just make a new empty one...
      versionNumber  = versionNumberFromFile(files.last) + 1;
      newMigrationFile = new File.fromUri(migrationDirectory.uri.resolve(
          "${"$versionNumber".padLeft(8, "0")}_Unnamed.migration.dart"));
    }

    var source = await generateMigrationSource(await schemaMapFromExistingMigrationFiles());
    List<String> tables = source["tablesEvaluated"];
    List<String> changeList = source["changeList"];

    displayInfo("The following ManagedObject<T> subclasses were found:");
    tables.forEach((t) => displayProgress(t));
    displayProgress("");
    displayProgress("* If you were expecting more declarations, ensure the files are visible in the application library file.");
    displayProgress("");

    changeList?.forEach((c) => displayProgress(c));

    newMigrationFile.writeAsStringSync(source["source"]);

    displayInfo(
        "Created new migration file (version ${versionNumberFromFile(newMigrationFile)}).",
        color: CLIColor.boldGreen);
    displayProgress("New file is located at ${newMigrationFile.path}");

    return 0;
  }

  Future<Map<String, dynamic>> generateMigrationSource(Map<String, dynamic> initialSchema) {
    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
      var inputSchema = new Schema.fromMap(values["initialSchema"]);
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);
      var changeList = <String>[];

      return {
        "source": SchemaBuilder.sourceForSchemaUpgrade(
            inputSchema, schema, 1, changeList: changeList),
        "tablesEvaluated" : dataModel
            .entities
            .map((e) => MirrorSystem.getName(e.instanceType.simpleName))
            .toList(),
        "changeList": changeList
      };
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName], message: {
      "initialSchema" : initialSchema
    }, packageConfigURI: projectDirectory.uri.resolve(".packages"));

    return executor.execute(projectDirectory.uri) as Future<Map<String, dynamic>>;
  }

  Future<Map<String, dynamic>> schemaMapFromExistingMigrationFiles() async {
    // build the schema by replaying migration files
    var schema = new Schema.empty();
    for (var migration in migrationFiles) {
      displayProgress("Replaying version ${versionNumberFromFile(migration)}");
      schema = await schemaByApplyingMigrationFile(
          projectDirectory, migration, schema, versionNumberFromFile(migration));
    }

    return schema.asMap();
  }

  String get name {
    return "generate";
  }

  String get detailedDescription {
    return "The migration file will upgrade the schema generated from running existing migration files match that of the schema in the current codebase.";
  }

  String get description {
    return "Creates a migration file.";
  }
}
