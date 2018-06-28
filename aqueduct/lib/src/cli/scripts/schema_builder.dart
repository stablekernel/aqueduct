import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/db/schema/migration_source.dart';
import 'package:isolate_executor/isolate_executor.dart';

class SchemaBuilderExecutable extends Executable {
  SchemaBuilderExecutable(Map<String, dynamic> message)
      : inputSchema = new Schema.fromMap(message["schema"]),
        sources = (message["sources"] as List<Map>).map((m) => new MigrationSource.fromMap(m)).toList(),
        super(message);

  final List<MigrationSource> sources;
  final Schema inputSchema;

  @override
  Future<dynamic> execute() async {
    hierarchicalLoggingEnabled = true;
    PostgreSQLPersistentStore.logger.level = Level.ALL;
    PostgreSQLPersistentStore.logger.onRecord.listen((r) => log("${r.message}"));

    var outputSchema = inputSchema;
    for (var source in sources) {
      Migration instance = instanceOf(source.name);
      instance.database = new SchemaBuilder(null, outputSchema);
      await instance.upgrade();
      outputSchema = instance.currentSchema;
    }
    return outputSchema.asMap();
  }

  static List<String> get imports =>
      ["package:aqueduct/aqueduct.dart", "package:aqueduct/src/db/schema/migration_source.dart"];

  static Map<String, dynamic> createMessage(List<MigrationSource> sources, Schema inputSchema) {
    return {"schema": inputSchema.asMap(), "sources": sources.map((ms) => ms.asMap()).toList()};
  }
}
