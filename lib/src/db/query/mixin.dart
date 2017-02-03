import '../managed/managed.dart';
import '../managed/backing.dart';

import 'query.dart';
import 'matcher_internal.dart';

abstract class QueryMixin<InstanceType extends ManagedObject>
    implements Query<InstanceType> {
  ManagedEntity _entity;
  ManagedEntity get entity =>
      _entity ?? context.dataModel.entityForType(InstanceType);

  bool canModifyAllInstances = false;
  int timeoutInSeconds = 30;
  int fetchLimit = 0;
  int offset = 0;
  QueryPage pageDescriptor;
  List<QuerySortDescriptor> sortDescriptors;
  Map<String, dynamic> valueMap;

  bool get hasWhereBuilder => _whereBuilder?.backingMap?.isNotEmpty ?? false;
  Map<ManagedRelationshipDescription, Query> subQueries;

  QueryPredicate predicate;

  List<String> _resultProperties;
  InstanceType _whereBuilder;
  InstanceType _valueObject;

  List<String> get propertiesToFetch {
    return _resultProperties ?? entity.defaultProperties;
  }

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

  QueryPredicate predicateFromMatcherBackedObject(ManagedObject obj, QueryMatcherTranslator translator) {
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

    var predicate = QueryPredicate.andPredicates(attributeKeys.map((queryKey) {
      var desc = entity.properties[queryKey];
      var matcher = obj.backingMap[queryKey];

      if (matcher is ComparisonMatcherExpression) {
        return translator.comparisonPredicate(desc, matcher.operator, matcher.value);
      } else if (matcher is RangeMatcherExpression) {
        return translator.rangePredicate(desc, matcher.lhs, matcher.rhs, matcher.within);
      } else if (matcher is NullMatcherExpression) {
        return translator.nullPredicate(desc, matcher.shouldBeNull);
      } else if (matcher is WithinMatcherExpression) {
        return translator.containsPredicate(desc, matcher.values);
      } else if (matcher is StringMatcherExpression) {
        return translator.stringPredicate(desc, matcher.operator, matcher.value);
      }

      throw new QueryPredicateException(
          "Unknown MatcherExpression ${matcher.runtimeType}");
    }).toList());

    var relationshipPredicates = obj.backingMap.keys.where((propertyName) {
      var desc = entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        return desc.relationshipType != ManagedRelationshipType.belongsTo;
      }

      return false;
    }).map((propertyName) {
      var innerObject = obj.backingMap[propertyName];
      if (innerObject is ManagedSet) {
        return predicateFromMatcherBackedObject(innerObject.matchOn, translator);
      }
      return predicateFromMatcherBackedObject(innerObject, translator);
    }).toList();

    if (relationshipPredicates.isEmpty) {
      return predicate;
    }

    var total = [predicate];
    total.addAll(relationshipPredicates);

    return QueryPredicate.andPredicates(total.where((q) => q != null).toList());
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
