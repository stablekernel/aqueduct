import 'package:wildfire/wildfire.dart';

main() {
  var dataModel = new DataModel.fromPackageContainingType(WildfireSink);
  var persistentStore = new PostgreSQLPersistentStore(() => null);

  var builder = new SchemaBuilder(persistentStore, new Schema.empty(), new Schema(dataModel));
  print("${builder.commands.join(";\n")}");
}