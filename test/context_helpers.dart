import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:postgres/postgres.dart';

Future<ManagedContext> contextWithModels(List<Type> instanceTypes) async {
  var persistentStore = new PostgreSQLPersistentStore(() async {
    var conn = new PostgreSQLConnection("localhost", 5432, "dart_test",
        username: "dart", password: "dart");
    await conn.open();
    return conn;
  });

  var dataModel = new ManagedDataModel(instanceTypes);
  var commands = commandsFromDataModel(dataModel, temporary: true);
  var context = new ManagedContext(dataModel, persistentStore);
  ManagedContext.defaultContext = context;

  for (var cmd in commands) {
    await persistentStore.execute(cmd);
  }

  return context;
}

List<String> commandsFromDataModel(ManagedDataModel dataModel,
    {bool temporary: false}) {
  var targetSchema = new Schema.fromDataModel(dataModel);
  var builder = new SchemaBuilder.toSchema(
      new PostgreSQLPersistentStore(() => null), targetSchema,
      isTemporary: temporary);
  return builder.commands;
}

List<String> commandsForModelInstanceTypes(List<Type> instanceTypes,
    {bool temporary: false}) {
  var dataModel = new ManagedDataModel(instanceTypes);
  return commandsFromDataModel(dataModel, temporary: temporary);
}
