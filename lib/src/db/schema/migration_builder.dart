import 'schema.dart';

class MigrationBuilder {
  static String sourceForSchemaUpgrade(
      Schema existingSchema, Schema newSchema, int version, {List<String> changeList}) {
    var diff = existingSchema.differenceFrom(newSchema);
    var source = diff.generateUpgradeSource(changeList: changeList);

    return """
import 'package:aqueduct/aqueduct.dart';   
import 'dart:async';

class Migration$version extends Migration { 
  Future upgrade() async {
   $source
  }
  
  Future downgrade() async {}
  Future seed() async {}
}
    """;
  }
}
