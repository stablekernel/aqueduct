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
  @override
  Future upgrade() async {
   $source
  }
  
  @override
  Future downgrade() async {}
  
  @override
  Future seed() async {}
}
    """;
  }
}
