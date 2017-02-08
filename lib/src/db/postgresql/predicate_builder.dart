import '../db.dart';

import 'property_mapper.dart';
import 'property_expression.dart';
import 'entity_table.dart';
import 'property_row.dart';

abstract class PredicateBuilder implements EntityTableMapper {
  ManagedEntity get entity;

  QueryPredicate predicateFrom(ManagedObject matcherObject, List<QueryPredicate> predicates, List<RowMapper> createdImplicitRowMappers) {
    var matchers = propertyExpressionsFromObject(matcherObject, createdImplicitRowMappers);
    var allPredicates = matchers.expand((p) => [p.predicate]).toList();
    allPredicates.addAll(predicates.where((p) => p != null));
    return QueryPredicate.andPredicates(allPredicates);
  }

  List<PropertyExpression> propertyExpressionsFromObject(
      ManagedObject obj, List<RowMapper> createdImplicitRowMappers, {bool disambiguateVariableNames: false}) {
    if (obj == null) {
      return [];
    }

    var prefix = disambiguateVariableNames ? "implicit_" : "";

    return obj.backingMap.keys.map((propertyName) {
      var desc = obj.entity.properties[propertyName];
      if (desc is ManagedRelationshipDescription) {
        if (desc.relationshipType == ManagedRelationshipType.belongsTo) {
          return [
            new PropertyExpression(
                this, obj.entity.properties[propertyName], obj.backingMap[propertyName], additionalVariablePrefix: prefix)
          ];
        }

        // Otherwise, this is an implicit join...
        // Do we have an existing guy?
        RowMapper innerRowMapper = returningOrderedMappers
            .where((m) => m is RowMapper)
            .firstWhere((m) => (m as RowMapper).representsRelationship(desc),
            orElse: () => null);
        bool disambiguate = true;
        if (innerRowMapper == null) {
          innerRowMapper = new RowMapper.implicit(PersistentJoinType.leftOuter, desc);
          innerRowMapper.parentTable = this;
          createdImplicitRowMappers.add(innerRowMapper);
          disambiguate = false;
        }

        var innerMatcher = obj.backingMap[propertyName];
        if (innerMatcher is ManagedSet) {
          return innerRowMapper.propertyExpressionsFromObject(
              innerMatcher.matchOn, createdImplicitRowMappers, disambiguateVariableNames: disambiguate);
        }

        return innerRowMapper.propertyExpressionsFromObject(
            innerMatcher, createdImplicitRowMappers, disambiguateVariableNames: disambiguate);
      }

      return [
        new PropertyExpression(
            this, obj.entity.properties[propertyName], obj.backingMap[propertyName], additionalVariablePrefix: prefix)
      ];
    })
    .expand((expressions) => expressions)
    .toList();
  }
}