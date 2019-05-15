import 'package:aqueduct/src/db/managed/managed.dart';

abstract class ManagedEntityRuntime {
  ManagedEntity get entity;
  ManagedObject instanceOfImplementation({ManagedBacking backing});
  ManagedSet setOfImplementation(Iterable<dynamic> objects);
  void setTransientValueForKey(ManagedObject object, String key, dynamic value);
  dynamic getTransientValueForKey(ManagedObject object, String key);
  bool isValueInstanceOf(dynamic value);
  bool isValueListOf(dynamic value);

  dynamic dynamicAccessorImplementation(Invocation invocation, ManagedEntity entity, ManagedObject object);
  dynamic dynamicConvertFromPrimitiveValue(ManagedPropertyDescription property, dynamic value);
}