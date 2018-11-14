import 'dart:async';

import 'package:aqueduct/aqueduct.dart';

Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
  var persistentStore =
      PostgreSQLPersistentStore("dart", "dart", "localhost", 5432, "dart_test");

  var dataModel = ManagedDataModel(instanceTypes);
  var commands = commandsFromDataModel(dataModel, temporary: true);
  var context = ManagedContext(dataModel, persistentStore);

  for (var cmd in commands) {
    await persistentStore.execute(cmd);
  }

  return context;
}

List<String> commandsFromDataModel(ManagedDataModel dataModel,
    {bool temporary = false}) {
  var targetSchema = Schema.fromDataModel(dataModel);
  var builder = SchemaBuilder.toSchema(
      PostgreSQLPersistentStore(null, null, null, 5432, null), targetSchema,
      isTemporary: temporary);
  return builder.commands;
}

List<String> commandsForModelInstanceTypes(List<Type> instanceTypes,
    {bool temporary = false}) {
  var dataModel = ManagedDataModel(instanceTypes);
  return commandsFromDataModel(dataModel, temporary: temporary);
}

Future dropSchemaTables(Schema schema, PersistentStore store) async {
  final tables = List<SchemaTable>.from(schema.tables);
  while (tables.isNotEmpty) {
    try {
      await store.execute("DROP TABLE IF EXISTS ${tables.last.name}");
      tables.removeLast();
    } catch (_) {
      tables.insert(0, tables.removeLast());
    }
  }
}