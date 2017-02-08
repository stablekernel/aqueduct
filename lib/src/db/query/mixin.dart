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
    subQueries ??= {};

    var property = m(where);
    var matchingKey = entity.relationships.keys.firstWhere((key) {
      return identical(where.backingMap[key], property);
    });

    var attr = entity.relationships[matchingKey];
    var subquery = new Query<T>(context);
    (subquery as QueryMixin)._entity = attr.destinationEntity;
    subQueries[attr] = subquery;

    return subquery;
  }

  Query<T> joinMany<T extends ManagedObject>(ManagedSet<T> m(InstanceType x)) {
    subQueries ??= {};

    var property = m(where);
    var matchingKey = entity.relationships.keys.firstWhere((key) {
      return identical(where.backingMap[key], property);
    });

    var attr = entity.relationships[matchingKey];
    var subquery = new Query<T>(context);
    (subquery as QueryMixin)._entity = attr.destinationEntity;
    subQueries[attr] = subquery;

    return subquery;
  }
}
