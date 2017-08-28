import 'schema.dart';

class MigrationBuilder {
  static String sourceForSchemaUpgrade(
      Schema existingSchema, Schema newSchema, int version, {List<String> changeList}) {
    var builder = new StringBuffer();
    builder.writeln("import 'package:aqueduct/aqueduct.dart';");
    builder.writeln("import 'dart:async';");
    builder.writeln("");
    builder.writeln("class Migration$version extends Migration {");
    builder.writeln("  Future upgrade() async {");

    var diff = existingSchema.differenceFrom(newSchema);
    var upgradeSource = diff.generateUpgradeSource(changeList: changeList);
    builder.write(upgradeSource);
    builder.write("\n");

    builder.writeln("  }");
    builder.writeln("");
    builder.writeln("  Future downgrade() async {");
    builder.writeln("  }");
    builder.writeln("  Future seed() async {");
    builder.writeln("  }");
    builder.writeln("}");

    return builder.toString();
  }
}
