import 'dart:async';
import 'dart:io';

import 'package:aqueduct/aqueduct.dart';

import '../cli_helpers.dart';

Future<CLIResult> executeMigrations(Directory projectDirectory) async {
  return runAqueductProcess([
    "db",
    "upgrade",
    "--connect",
    "postgres://dart:dart@localhost:5432/dart_test"
  ], projectDirectory);
}

Future writeMigrations(
    Directory migrationDirectory, List<Schema> schemas) async {
  var currentNumberOfMigrations = migrationDirectory
      .listSync()
      .where((e) => e.path.endsWith("migration.dart"))
      .length;

  for (var i = 1; i < schemas.length; i++) {
    var source = await MigrationBuilder.sourceForSchemaUpgrade(
        schemas[i - 1], schemas[i], i);

    var file = new File.fromUri(migrationDirectory.uri
        .resolve("${i + currentNumberOfMigrations}.migration.dart"));
    file.writeAsStringSync(source);
  }
}