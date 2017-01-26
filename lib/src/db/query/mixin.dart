import '../managed/managed.dart';
import '../managed/backing.dart';

import 'query.dart';
import 'matcher_internal.dart';

abstract class QueryMixin<InstanceType extends ManagedObject>
    implements Query<InstanceType>, QueryMatcherTranslator {
  ManagedEntity _entity;
  ManagedEntity get entity => _entity ?? context.dataModel.entityForType(InstanceType);

  bool canModifyAllInstances = false;
  int timeoutInSeconds = 30;
  int fetchLimit = 0;
  int offset = 0;
  QueryPage pageDescriptor;
  List<QuerySortDescriptor> sortDescriptors;
  Map<String, dynamic> valueMap;
  Map<Type, List<String>> nestedResultProperties = {};

  bool get hasWhereBuilder => _whereBuilder != null;
  Map<ManagedRelationshipDescription, Query> subQueries;

  QueryPredicate _predicate;
  List<String> _resultProperties;
  InstanceType _whereBuilder;
  InstanceType _valueObject;

  QueryPredicate get predicate {
    if (_whereBuilder != null) {
      _predicate = predicateFromMatcherBackedObject(where);
    }

    return _predicate;
  }

  void set predicate(QueryPredicate p) {
    _predicate = p;
  }

  List<String> get resultProperties {
    return _resultProperties ?? entity.defaultProperties;
  }

  void set resultProperties(List<String> props) {
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
      return where.backingMap[key] == property;
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
      return where.backingMap[key] == property;
    });

    var attr = entity.relationships[matchingKey];
    var subquery = new Query<T>(context);
    (subquery as QueryMixin)._entity = attr.destinationEntity;
    subQueries[attr] = subquery;

    return subquery;
  }

  QueryPredicate predicateFromMatcherBackedObject(QueryMatchable obj) {
    if (obj == null) {
      return null;
    }

    var entity = obj.entity;
    var attributeKeys = obj.backingMap.keys.where((propertyName) {
      var desc = entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        return desc.relationshipType == ManagedRelationshipType.belongsTo;
      }

      return true;
    });

    return QueryPredicate.andPredicates(attributeKeys.map((queryKey) {
      var desc = entity.properties[queryKey];
      var matcher = obj.backingMap[queryKey];

      if (matcher is ComparisonMatcherExpression) {
        return comparisonPredicate(desc, matcher.operator, matcher.value);
      } else if (matcher is RangeMatcherExpression) {
        return rangePredicate(desc, matcher.lhs, matcher.rhs, matcher.within);
      } else if (matcher is NullMatcherExpression) {
        return nullPredicate(desc, matcher.shouldBeNull);
      } else if (matcher is WithinMatcherExpression) {
        return containsPredicate(desc, matcher.values);
      } else if (matcher is StringMatcherExpression) {
        return stringPredicate(desc, matcher.operator, matcher.value);
      }

      throw new QueryPredicateException(
          "Unknown MatcherExpression ${matcher.runtimeType}");
    }).toList());
  }
}

abstract class QueryMatcherTranslator {
  QueryPredicate comparisonPredicate(
      ManagedPropertyDescription desc, MatcherOperator operator, dynamic value);
  QueryPredicate containsPredicate(
      ManagedPropertyDescription desc, Iterable<dynamic> values);
  QueryPredicate nullPredicate(ManagedPropertyDescription desc, bool isNull);
  QueryPredicate rangePredicate(ManagedPropertyDescription desc,
      dynamic lhsValue, dynamic rhsValue, bool insideRange);
  QueryPredicate stringPredicate(ManagedPropertyDescription desc,
      StringMatcherOperator operator, dynamic value);
}
