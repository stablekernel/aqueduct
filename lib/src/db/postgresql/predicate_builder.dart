import '../db.dart';
import '../managed/backing.dart';
import '../query/matcher_internal.dart';
import 'entity_table.dart';
import 'property_expression.dart';
import 'property_mapper.dart';
import 'row_mapper.dart';

abstract class PredicateBuilder implements EntityTableMapper {
  ManagedEntity get entity;

  List<PropertyExpression> propertyExpressionsFromObject(
      ManagedObject obj, List<RowMapper> createdImplicitRowMappers,
      {bool disambiguateVariableNames: false}) {
    if (obj == null) {
      return [];
    }

    var prefix = disambiguateVariableNames ? "implicit_" : "";

    return obj.backingMap.keys
        .map((propertyName) {
          var desc = obj.entity.properties[propertyName];
          if (desc is ManagedRelationshipDescription) {
            if (desc.relationshipType == ManagedRelationshipType.belongsTo) {
              return [
                new PropertyExpression(
                    this,
                    obj.entity.properties[propertyName],
                    obj.backingMap[propertyName],
                    additionalVariablePrefix: prefix)
              ];
            }

            // Otherwise, this is an implicit join...
            // Do we have an existing guy?
            bool disambiguate = true;
            RowMapper innerRowMapper = returningOrderedMappers
                .where((m) => m is RowMapper)
                .firstWhere(
                    (m) => (m as RowMapper).representsRelationship(desc),
                    orElse: () => null);

            if (innerRowMapper == null) {
              innerRowMapper =
                  new RowMapper.implicit(PersistentJoinType.leftOuter, desc);
              innerRowMapper.parentTable = this;
              createdImplicitRowMappers.add(innerRowMapper);
              disambiguate = false;
            }

            var innerMatcher = obj.backingMap[propertyName];
            if (innerMatcher is NullMatcherExpression) {
              innerMatcher = new ManagedObject()
                ..entity = desc.inverseRelationship.entity
                ..backing = new ManagedMatcherBacking()
                ..[desc.inverseRelationship.name] = innerMatcher;
            }

            if (innerMatcher is ManagedSet) {
              innerMatcher = (innerMatcher as ManagedSet).matchOn;
            }

            return innerRowMapper.propertyExpressionsFromObject(
                innerMatcher, createdImplicitRowMappers,
                disambiguateVariableNames: disambiguate);
          }

          return [
            new PropertyExpression(this, obj.entity.properties[propertyName],
                obj.backingMap[propertyName],
                additionalVariablePrefix: prefix)
          ];
        })
        .expand((expressions) => expressions)
        .toList();
  }
}
