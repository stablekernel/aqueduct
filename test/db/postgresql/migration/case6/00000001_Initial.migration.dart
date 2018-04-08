import 'package:aqueduct/aqueduct.dart';
import 'dart:async';

class Migration1 extends Migration {
  @override
  Future upgrade() async {
    database.createTable(new SchemaTable(
      "_TestObject",
      [
        new SchemaColumn("id", ManagedPropertyType.bigInteger,
            isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
        new SchemaColumn("foo", ManagedPropertyType.string,
            isPrimaryKey: false, autoincrement: false, isIndexed: false, isNullable: false, isUnique: false),
      ],
    ));
  }

  @override
  Future downgrade() async {}

  @override
  Future seed() async {}
}
