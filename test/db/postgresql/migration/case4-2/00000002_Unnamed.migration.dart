import 'package:aqueduct/aqueduct.dart';   
import 'dart:async';

class Migration2 extends Migration { 
  @override
  Future upgrade() async {
   database.createTable(new SchemaTable("_Foo", [
new SchemaColumn("id", ManagedPropertyType.bigInteger, isPrimaryKey: true, autoincrement: true, isIndexed: false, isNullable: false, isUnique: false),
new SchemaColumn.relationship("testObject", ManagedPropertyType.bigInteger, relatedTableName: "_TestObject", relatedColumnName: "id", rule: DeleteRule.nullify, isNullable: true, isUnique: true),
],
));


  }
  
  @override
  Future downgrade() async {}
  
  @override
  Future seed() async {}
}
    