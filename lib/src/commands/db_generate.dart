import 'dart:async';
import 'dart:io';
import 'dart:mirrors';

import '../db/db.dart';
import '../utilities/source_generator.dart';
import 'base.dart';
import 'db.dart';


/*
The following types were evaluated:
  - User
    - Name changed to: XYZ
    - Added: ColumnName
    - Removed: ColumnName
  - Foo
    - No Changes
  - XYZ
    - No Changes
 */

class CLIDatabaseGenerate extends CLICommand
    with CLIDatabaseMigratable, CLIProject {
  Future<int> handle() async {
    var files = migrationFiles;

    if (!files.isEmpty) {
      // For now, just make a new empty one...
      var newVersionNumber = versionNumberFromFile(files.last) + 1;
      var contents = SchemaBuilder.sourceForSchemaUpgrade(
          new Schema.empty(), new Schema.empty(), newVersionNumber);
      var file = new File.fromUri(migrationDirectory.uri.resolve(
          "${"$newVersionNumber".padLeft(8, "0")}_Unnamed.migration.dart"));
      file.writeAsStringSync(contents);

      displayInfo("Created new migration file ${file.uri}.");
      return 0;
    }

    var file = new File.fromUri(
        migrationDirectory.uri.resolve("00000001_Initial.migration.dart"));
    var source = await generateMigrationSource();
    List<String> tables = source["tablesEvaluated"];

    displayInfo("The following ManagedObject<T> subclasses were found:");
    tables.forEach((t) => displayProgress(t));
    displayProgress("");
    displayProgress("* If you were expecting more declarations, ensure the files are visible in the application library file.");
    displayProgress("");

    file.writeAsStringSync(source["source"]);

    displayInfo(
        "Created new migration file (version ${versionNumberFromFile(file)}).",
        color: CLIColor.boldGreen);
    displayProgress("New file is located at ${file.path}");

    return 0;
  }

  Future<Map<String, dynamic>> generateMigrationSource() {
    var generator = new SourceGenerator(
        (List<String> args, Map<String, dynamic> values) async {
      var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
      var schema = new Schema.fromDataModel(dataModel);

      return {
        "source": SchemaBuilder.sourceForSchemaUpgrade(
            new Schema.empty(), schema, 1),
        "tablesEvaluated" : dataModel
            .entities
            .map((e) => MirrorSystem.getName(e.instanceType.simpleName))
            .toList()
      };
    }, imports: [
      "package:aqueduct/aqueduct.dart",
      "package:$libraryName/$libraryName.dart",
      "dart:isolate",
      "dart:mirrors",
      "dart:async"
    ]);

    var executor = new IsolateExecutor(generator, [libraryName],
        packageConfigURI: projectDirectory.uri.resolve(".packages"));

    return executor.execute(projectDirectory.uri) as Future<Map<String, dynamic>>;
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
