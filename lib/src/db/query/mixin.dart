import 'dart:mirrors';

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
      _whereBuilder = entity.newInstance(backing: new ManagedMatcherBacking()) as InstanceType;
    }
    return _whereBuilder;
  }

  @override
  Query<T> join<T extends ManagedObject>({T object(InstanceType x), ManagedSet<T> set(InstanceType x)}) {
    final desc = _selectRelationship(object ?? set);

    return _createSubquery(desc);
  }

  @override
  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order, {T boundingValue}) {
    final attribute = _selectAttribute(propertyIdentifier);
    pageDescriptor = new QueryPage(order, attribute.name, boundingValue: boundingValue);
  }

  @override
  void sortBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order) {
    final attribute = _selectAttribute(propertyIdentifier);

    sortDescriptors ??= <QuerySortDescriptor>[];
    sortDescriptors.add(new QuerySortDescriptor(attribute.name, order));
  }

  @override
  void returningProperties(List<dynamic> propertyIdentifiers(InstanceType x)) {
    _propertiesToFetch = _selectProperties(propertyIdentifiers).map((p) => p.name).toList();
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

  ManagedAttributeDescription _selectAttribute<T>(T propertyIdentifier(InstanceType x)) {
    var obj = entity.newInstance(backing: new ManagedAccessTrackingBacking());
    var propertyName = propertyIdentifier(obj as InstanceType) as String;

    var attribute = entity.attributes[propertyName];
    if (attribute == null) {
      if (entity.relationships.containsKey(propertyName)) {
        throw new ArgumentError(
            "Invalid property selection. Property '$propertyName' on "
                "'${MirrorSystem.getName(entity.instanceType.simpleName)}' "
                "is a relationship and cannot be selected for this operation.");
      } else {
        throw new ArgumentError(
            "Invalid property selection. Column '$propertyName' does not "
                "exist on table '${entity.tableName}'.");
      }
    }

    return attribute;
  }

  ManagedRelationshipDescription _selectRelationship<T>(T propertyIdentifier(InstanceType x)) {
    var obj = entity.newInstance(backing: new ManagedAccessTrackingBacking());
    var matchingKey = propertyIdentifier(obj as InstanceType) as String;

    var desc = entity.relationships[matchingKey];
    if (desc == null) {
      throw new ArgumentError("Invalid property selection. Relationship named '$matchingKey' on table '${entity
          .tableName}' is not a relationship.");
    }

    return desc;
  }

  List<ManagedPropertyDescription> _selectProperties<T>(T propertiesIdentifier(InstanceType x)) {
    var obj = entity.newInstance(backing: new ManagedAccessTrackingBacking());
    var propertyNames = propertiesIdentifier(obj as InstanceType) as List<String>;

    return propertyNames.map((name) {
      final prop = entity.properties[name];
      if (prop == null) {
        throw new ArgumentError("Invalid property selection. The property '$name' does not exist on "
            "'${MirrorSystem.getName(entity.instanceType.simpleName)}'.");
      }
      return prop;
    }).toList();
  }
}
