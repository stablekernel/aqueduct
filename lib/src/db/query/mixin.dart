import '../managed/backing.dart';
import '../managed/managed.dart';
import 'page.dart';
import 'query.dart';
import 'sort_descriptor.dart';

abstract class QueryMixin<InstanceType extends ManagedObject> implements Query<InstanceType> {
  @override
  int offset = 0;

  @override
  int fetchLimit = 0;

  @override
  int timeoutInSeconds = 30;

  @override
  bool canModifyAllInstances = false;

  @override
  Map<String, dynamic> valueMap;

  @override
  QueryPredicate predicate;

  QueryPage pageDescriptor;
  List<QuerySortDescriptor> sortDescriptors;
  Map<ManagedRelationshipDescription, Query> subQueries;

  QueryMixin _parentQuery;
  InstanceType _whereBuilder;
  InstanceType _valueObject;

  bool get hasWhereBuilder => _whereBuilder?.backingMap?.isNotEmpty ?? false;

  List<String> _propertiesToFetch;

  List<String> get propertiesToFetch => _propertiesToFetch ?? entity.defaultProperties;

  @override
  InstanceType get values {
    if (_valueObject == null) {
      _valueObject = entity.newInstance() as InstanceType;
    }
    return _valueObject;
  }

  @override
  set values(InstanceType obj) {
    _valueObject = obj;
  }

  @override
  InstanceType get where {
    if (_whereBuilder == null) {
      _whereBuilder = entity.newInstance() as InstanceType;
      _whereBuilder.backing = new ManagedMatcherBacking();
    }
    return _whereBuilder;
  }

  @override
  Query<T> join<T extends ManagedObject>({T object(InstanceType x), ManagedSet<T> set(InstanceType x)}) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var matchingKey;
    if (object != null) {
      matchingKey = object(obj as InstanceType) as String;
    } else if (set != null) {
      matchingKey = set(obj as InstanceType) as String;
    }

    var attr = entity.relationships[matchingKey];
    if (attr == null) {
      throw new ArgumentError("Invalid join query. Relationship named '$matchingKey' on table '${entity
          .tableName}' is not a relationship.");
    }

    return _createSubquery(attr);
  }

  @override
  Query<T> joinOne<T extends ManagedObject>(T m(InstanceType x)) {
    return join(object: m);
  }

  @override
  Query<T> joinMany<T extends ManagedObject>(ManagedSet<T> m(InstanceType x)) {
    return join(set: m);
  }

  @override
  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order, {T boundingValue}) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyName = propertyIdentifier(obj as InstanceType) as String;

    var attribute = entity.attributes[propertyName];
    if (attribute == null) {
      if (entity.relationships[propertyName] != null) {
        throw new ArgumentError(
            "Invalid query pageBy. Column '$propertyName' does not exist on table '${entity.tableName}'. "
            "'$propertyName' recognized as ORM relationship and is therefore are not pageable.");
      } else {
        throw new ArgumentError(
            "Invalid query pageBy. Column '$propertyName' does not exist on table '${entity.tableName}'.");
      }
    }

    pageDescriptor = new QueryPage(order, propertyName, boundingValue: boundingValue);
  }

  @override
  void sortBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyName = propertyIdentifier(obj as InstanceType) as String;

    var attribute = entity.attributes[propertyName];
    if (attribute == null) {
      if (entity.relationships[propertyName] != null) {
        throw new ArgumentError(
            "Invalid query sortBy. Column '$propertyName' does not exist on table '${entity.tableName}'. "
            "'$propertyName' recognized as ORM relationship and is therefore are not pageable.");
      } else {
        throw new ArgumentError(
            "Invalid query sortBy. Column '$propertyName' does not exist on table '${entity.tableName}'.");
      }
    }

    sortDescriptors ??= <QuerySortDescriptor>[];
    sortDescriptors.add(new QuerySortDescriptor(propertyName, order));
  }

  @override
  void returningProperties(List<dynamic> propertyIdentifiers(InstanceType x)) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyNames = propertyIdentifiers(obj as InstanceType) as List<String>;

    _propertiesToFetch = propertyNames;
  }

  void validateInput(ValidateOperation op) {
    if (valueMap == null) {
      if (op == ValidateOperation.insert) {
        values.willInsert();
      } else if (op == ValidateOperation.update) {
        values.willUpdate();
      }

      var errors = <String>[];
      if (!values.validate(forOperation: op, collectErrorsIn: errors)) {
        throw new ValidationException(errors);
      }
    }
  }

  Query _createSubquery(ManagedRelationshipDescription fromRelationship) {
    // Ensure we don't cyclically join
    var parent = _parentQuery;
    while (parent != null) {
      if (parent.subQueries.containsKey(fromRelationship.inverse)) {
        var validJoins = fromRelationship.entity.relationships.values
            .where((r) => !identical(r, fromRelationship))
            .map((r) => "'${r.name}'")
            .join(", ");

        throw new StateError("Invalid query construction. This query joins '${fromRelationship.entity.tableName}' "
            "with '${fromRelationship.inverse.entity.tableName}' on property '${fromRelationship.name}'. "
            "However, '${fromRelationship.inverse.entity.tableName}' "
            "has also joined '${fromRelationship.entity.tableName}' on this property's inverse "
            "'${fromRelationship.inverse.name}' earlier in the 'Query'. "
            "Perhaps you meant to join on another property, such as: $validJoins?");
      }

      parent = parent._parentQuery;
    }

    subQueries ??= {};

    var subquery = new Query.forEntity(fromRelationship.destinationEntity, context);
    (subquery as QueryMixin)._parentQuery = this;
    subQueries[fromRelationship] = subquery;

    return subquery;
  }
}
