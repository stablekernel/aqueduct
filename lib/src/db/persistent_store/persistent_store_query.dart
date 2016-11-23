import 'persistent_store.dart';
import '../query/query.dart';
import '../managed/managed.dart';
import '../managed/query_matchable.dart';

/// This enumeration is used internaly.
enum PersistentJoinType { leftOuter }

/// This class is used internally to map [Query] to something a [PersistentStore] can execute.
class PersistentStoreQuery {
  int offset = 0;
  int fetchLimit = 0;
  int timeoutInSeconds = 30;
  bool confirmQueryModifiesAllInstancesOnDeleteOrUpdate;
  ManagedEntity entity;
  QueryPage pageDescriptor;
  QueryPredicate predicate;
  List<QuerySortDescriptor> sortDescriptors;
  List<PersistentColumnMapping> values;
  List<PersistentColumnMapping> resultKeys;
}

/// This class is used internally.
class PersistentColumnMapping {
  PersistentColumnMapping(this.property, this.value);
  PersistentColumnMapping.fromElement(
      PersistentColumnMapping original, this.value) {
    property = original.property;
  }

  ManagedPropertyDescription property;
  dynamic value;

  String toString() {
    return "MappingElement on $property (Value = $value)";
  }
}

/// This class is used internally.
class PersistentJoinMapping extends PersistentColumnMapping {
  PersistentJoinMapping(this.type, ManagedPropertyDescription property,
      this.predicate, this.resultKeys)
      : super(property, null) {
    var primaryKeyElement = this.resultKeys.firstWhere((e) {
      var eProp = e.property;
      if (eProp is ManagedAttributeDescription) {
        return eProp.isPrimaryKey;
      }
      return false;
    });

    primaryKeyIndex = this.resultKeys.indexOf(primaryKeyElement);
  }

  PersistentJoinMapping.fromElement(
      PersistentJoinMapping original, List<PersistentColumnMapping> values)
      : super.fromElement(original, values) {
    type = original.type;
    primaryKeyIndex = original.primaryKeyIndex;
  }

  PersistentJoinType type;
  ManagedPropertyDescription get joinProperty =>
      (property as ManagedRelationshipDescription).inverseRelationship;
  QueryPredicate predicate;
  List<PersistentColumnMapping> resultKeys;

  int primaryKeyIndex;
  List<PersistentColumnMapping> get values =>
      value as List<PersistentColumnMapping>;
}
