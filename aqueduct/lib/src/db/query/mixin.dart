import 'package:aqueduct/src/db/managed/key_path.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

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
  List<QueryExpression<dynamic, dynamic>> expressions = [];
  InstanceType _valueObject;

  List<KeyPath> _propertiesToFetch;

  List<KeyPath> get propertiesToFetch => _propertiesToFetch ?? entity.defaultProperties.map((k) => new KeyPath(entity.properties[k])).toList();

  @override
  InstanceType get values {
    if (_valueObject == null) {
      _valueObject = entity.instanceOf() as InstanceType;
      _valueObject.backing = new ManagedBuilderBacking.from(_valueObject.entity, _valueObject.backing);
    }
    return _valueObject;
  }

  @override
  set values(InstanceType obj) {
    _valueObject = entity.instanceOf(backing: new ManagedBuilderBacking.from(entity, obj.backing));
  }

  @override
  QueryExpression<T, InstanceType> where<T>(T propertyIdentifier(InstanceType x)) {
    final properties = entity.identifyProperties(propertyIdentifier);
    if (properties.length != 1) {
      throw new ArgumentError("Invalid property selector. Must reference a single property only.");
    }

    final expr = new QueryExpression<T, InstanceType>(properties.first);
    expressions.add(expr);
    return expr;
  }

  @override
  Query<T> join<T extends ManagedObject>({T object(InstanceType x), ManagedSet<T> set(InstanceType x)}) {
    final desc = entity.identifyRelationship(object ?? set);

    return _createSubquery<T>(desc);
  }

  @override
  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order, {T boundingValue}) {
    final attribute = entity.identifyAttribute(propertyIdentifier);
    pageDescriptor = new QueryPage(order, attribute.name, boundingValue: boundingValue);
  }

  @override
  void sortBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order) {
    final attribute = entity.identifyAttribute(propertyIdentifier);

    sortDescriptors ??= <QuerySortDescriptor>[];
    sortDescriptors.add(new QuerySortDescriptor(attribute.name, order));
  }

  @override
  void returningProperties(List<dynamic> propertyIdentifiers(InstanceType x)) {
    final properties = entity.identifyProperties(propertyIdentifiers);

    if (properties.any((kp) => kp.path.any((p) => p is ManagedRelationshipDescription && p.relationshipType != ManagedRelationshipType.belongsTo))) {
      throw new ArgumentError("Invalid property selector. Cannot select has-many or has-one relationship properties. Use join instead.");
    }

    _propertiesToFetch = entity.identifyProperties(propertyIdentifiers);
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

  Query<T> _createSubquery<T extends ManagedObject>(ManagedRelationshipDescription fromRelationship) {
    if (subQueries?.containsKey(fromRelationship) ?? false) {
      throw new StateError("Invalid query. Cannot join same property more than once.");
    }

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

    var subquery = new Query<T>(context);
    (subquery as QueryMixin)._parentQuery = this;
    subQueries[fromRelationship] = subquery;

    return subquery;
  }
}
