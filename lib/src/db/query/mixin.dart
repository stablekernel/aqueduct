import '../managed/managed.dart';
import '../managed/backing.dart';

import 'query.dart';

abstract class QueryMixin<InstanceType extends ManagedObject>
    implements Query<InstanceType> {
  ManagedEntity _entity;
  ManagedEntity get entity =>
      _entity ?? context.dataModel.entityForType(InstanceType);

  int offset = 0;
  int fetchLimit = 0;
  int timeoutInSeconds = 30;
  bool canModifyAllInstances = false;

  QueryPage pageDescriptor;
  List<QuerySortDescriptor> sortDescriptors;
  Map<String, dynamic> valueMap;
  Map<ManagedRelationshipDescription, Query> subQueries;
  QueryPredicate predicate;

  QueryMixin _parentQuery;
  List<String> _resultProperties;
  InstanceType _whereBuilder;
  InstanceType _valueObject;

  bool get hasWhereBuilder => _whereBuilder?.backingMap?.isNotEmpty ?? false;

  List<String> get propertiesToFetch =>
      _resultProperties ?? entity.defaultProperties;

  void set propertiesToFetch(List<String> props) {
    _resultProperties = props;
  }

  InstanceType get values {
    if (_valueObject == null) {
      _valueObject = entity.newInstance() as InstanceType;
    }
    return _valueObject;
  }

  void set values(InstanceType obj) {
    _valueObject = obj;
  }

  InstanceType get where {
    if (_whereBuilder == null) {
      _whereBuilder = entity.newInstance() as InstanceType;
      _whereBuilder.backing = new ManagedMatcherBacking();
    }
    return _whereBuilder;
  }

  Query<T> joinOn<T extends ManagedObject>(T m(InstanceType x)) {
    var attr = _relationshipPropertyForProperty(m(where));
    return _createSubquery(attr);
  }

  Query<T> joinMany<T extends ManagedObject>(ManagedSet<T> m(InstanceType x)) {
    var attr = _relationshipPropertyForProperty(m(where));
    return _createSubquery(attr);
  }

  ManagedRelationshipDescription _relationshipPropertyForProperty(dynamic property) {
    var matchingKey = entity.relationships.keys.firstWhere((key) {
      return identical(where.backingMap[key], property);
    });

    return entity.relationships[matchingKey];
  }

  Query _createSubquery(ManagedRelationshipDescription fromRelationship) {
    // Ensure we don't cyclically join
    var parent = _parentQuery;
    while (parent != null) {
      if (parent.subQueries.containsKey(fromRelationship.inverse)) {
        var validJoins = fromRelationship.entity.relationships.values
            .where((r) => !identical(r, fromRelationship))
            .map((r) => "'${r.name}'").join(", ");

        throw new QueryException(QueryExceptionEvent.internalFailure,
            message: "Invalid cyclic 'Query'. This query joins '${fromRelationship.entity.tableName}' "
                "with '${fromRelationship.inverse.entity.tableName}' on property '${fromRelationship.name}'. "
                "However, '${fromRelationship.inverse.entity.tableName}' "
                "has also joined '${fromRelationship.entity.tableName}' on this property's inverse "
                "'${fromRelationship.inverse.name}' earlier in the 'Query'. "
                "Perhaps you meant to join on another property, such as: ${validJoins}?");
      }

      parent = parent._parentQuery;
    }

    subQueries ??= {};

    var subquery = new Query(context);
    (subquery as QueryMixin)
      .._entity = fromRelationship.destinationEntity
      .._parentQuery = this;
    subQueries[fromRelationship] = subquery;

    return subquery;
  }
}
