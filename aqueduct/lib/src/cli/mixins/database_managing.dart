import 'dart:async';
import 'dart:io';

import 'package:aqueduct/src/cli/command.dart';
import 'package:aqueduct/src/cli/metadata.dart';
import 'package:aqueduct/src/cli/mixins/project.dart';
import 'package:aqueduct/src/cli/scripts/schema_builder.dart';
import 'package:aqueduct/src/cli/migration_source.dart';
import 'package:aqueduct/src/db/schema/schema.dart';
import 'package:isolate_executor/isolate_executor.dart';

abstract class CLIDatabaseManagingCommand implements CLICommand, CLIProject {
  @Option("migration-directory",
      help:
          "The directory where migration files are stored. Relative paths are relative to the application-directory.",
      defaultsTo: "migrations")
  Directory get migrationDirectory {
    final dir = Directory(decode("migration-directory")).absolute;

    if (!dir.existsSync()) {
      dir.createSync();
    }
    return dir;
  }

  List<MigrationSource> get projectMigrations {
    try {
      final pattern = RegExp(r"^[0-9]+[_a-zA-Z0-9]*\.migration\.dart$");
      final sources = migrationDirectory
          .listSync()
          .where((fse) =>
              fse is File && pattern.hasMatch(fse.uri.pathSegments.last))
          .map((fse) => MigrationSource.fromFile(fse.absolute.uri))
          .toList();

      sources.sort((s1, s2) => s1.versionNumber.compareTo(s2.versionNumber));

      return sources;
    } on StateError catch (e) {
      throw CLIException(e.message);
    }
  }

  Future<Schema> schemaByApplyingMigrationSources(List<MigrationSource> sources,
      {Schema fromSchema}) async {
    fromSchema ??= Schema.empty();

    if (sources.isNotEmpty) {
      displayProgress(
          "Replaying versions: ${sources.map((f) => f.versionNumber.toString()).join(", ")}...");
    }

    final schemaMap = await IsolateExecutor.run(
        SchemaBuilderExecutable.input(sources, fromSchema),
        packageConfigURI: packageConfigUri,
        imports: SchemaBuilderExecutable.imports,
        additionalContents: MigrationSource.combine(sources),
        logHandler: displayProgress);

    if (schemaMap.containsKey("error")) {
      throw CLIException(schemaMap["error"] as String);
    }

    return Schema.fromMap(schemaMap);
  }
}
