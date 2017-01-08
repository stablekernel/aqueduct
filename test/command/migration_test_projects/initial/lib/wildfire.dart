import 'package:aqueduct/aqueduct.dart';

class TestObject extends ManagedObject<_TestObject> {}

class _TestObject {
  @managedPrimaryKey
  int id;

  String foo;
}
