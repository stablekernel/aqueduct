import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:isolate_executor/isolate_executor.dart';

class SchemaBuilderExecutable extends Executable<Map<String, dynamic>> {
  SchemaBuilderExecutable(Map<String, dynamic> message)
      : inputSchema = Schema.fromMap(message["schema"] as Map<String, dynamic>),
        sources = (message["sources"] as List<Map>)
            .map((m) => MigrationSource.fromMap(m as Map<String, dynamic>))
            .toList(),
        super(message);

  SchemaBuilderExecutable.input(this.sources, this.inputSchema)
      : super({
          "schema": inputSchema.asMap(),
          "sources": sources.map((source) => source.asMap()).toList()
        });

  final List<MigrationSource> sources;
  final Schema inputSchema;

  @override
  Future<Map<String, dynamic>> execute() async {
    hierarchicalLoggingEnabled = true;
    PostgreSQLPersistentStore.logger.level = Level.ALL;
    PostgreSQLPersistentStore.logger.onRecord
        .listen((r) => log("${r.message}"));

    var outputSchema = inputSchema;
    for (var source in sources) {
      Migration instance = instanceOf(source.name);
      instance.database = SchemaBuilder(null, outputSchema);
      await instance.upgrade();
      outputSchema = instance.currentSchema;
    }
    return outputSchema.asMap();
  }

  static List<String> get imports => [
        "package:aqueduct/aqueduct.dart",
        "package:aqueduct/src/db/schema/migration_source.dart"
      ];
}
