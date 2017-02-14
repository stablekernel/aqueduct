import '../managed/backing.dart';
import '../managed/managed.dart';
import 'page.dart';
import 'query.dart';
import 'sort_descriptor.dart';

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

  InstanceType _whereBuilder;
  InstanceType _valueObject;

  bool get hasWhereBuilder => _whereBuilder?.backingMap?.isNotEmpty ?? false;

  List<String> _propertiesToFetch;
  List<String> get propertiesToFetch =>
      _propertiesToFetch ?? entity.defaultProperties;

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

  void pageBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order,
      {T boundingValue}) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyName = propertyIdentifier(obj as InstanceType) as String;

    var attribute = entity.attributes[propertyName];
    if (attribute == null) {
      if (entity.relationships[propertyName] != null) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Property '${propertyName}' cannot be paged on for ${entity.tableName}. "
                "Reason: relationship properties cannot be paged on.");
      } else {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Property '${propertyName}' cannot be paged on for ${entity.tableName}. "
                "Reason: property does not exist for entity.");
      }
    }

    pageDescriptor =
        new QueryPage(order, propertyName, boundingValue: boundingValue);
  }

  void sortBy<T>(T propertyIdentifier(InstanceType x), QuerySortOrder order) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyName = propertyIdentifier(obj as InstanceType) as String;

    var attribute = entity.attributes[propertyName];
    if (attribute == null) {
      if (entity.relationships[propertyName] != null) {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Property '${propertyName}' cannot be paged on for ${entity.tableName}. "
                "Reason: relationship properties cannot be paged on.");
      } else {
        throw new QueryException(QueryExceptionEvent.internalFailure,
            message:
                "Property '${propertyName}' cannot be paged on for ${entity.tableName}. "
                "Reason: property does not exist for entity.");
      }
    }

    sortDescriptors ??= <QuerySortDescriptor>[];
    sortDescriptors.add(new QuerySortDescriptor(propertyName, order));
  }

  void returningProperties(List<dynamic> propertyIdentifiers(InstanceType x)) {
    var tracker = new ManagedAccessTrackingBacking();
    var obj = entity.newInstance()..backing = tracker;
    var propertyNames = propertyIdentifiers(obj as InstanceType) as List<String>;

    _propertiesToFetch = propertyNames;
  }

}
