import 'package:wildfire/wildfire.dart';
import 'dart:io';

main() {
  var dataModel = new DataModel(WildfirePipeline.modelTypes());
  var persistentStore = new PostgreSQLPersistentStore(() => null);
  var ctx = new ModelContext(dataModel, persistentStore);

  var generator = new SchemaGenerator(ctx.dataModel);
  var json = generator.serialized;
  var pGenerator = new PostgreSQLSchemaGenerator(json);

  var schemaFile = new File("schema.sql");
  schemaFile.writeAsStringSync(pGenerator.commandList);
}