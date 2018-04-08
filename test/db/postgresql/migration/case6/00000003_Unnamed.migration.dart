import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

class Migration3 extends Migration {
  @override
  Future upgrade() async {
    database.addColumn(
        "_Foo",
        new SchemaColumn("name", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
        unencodedInitialValue: "0");
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}
