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
          var innerMatcher = obj.backingMap[propertyName];

          if (desc is ManagedAttributeDescription) {
            return [
              new PropertyExpression(this, obj.entity.properties[propertyName],
                  obj.backingMap[propertyName],
                  additionalVariablePrefix: prefix)
            ];
          }

          // But if it is a relationship and only the primary key value is set, then we can do t
          // this without the join.. its just the foreign key column
          var relationshipDesc = desc as ManagedRelationshipDescription;
          if (relationshipDesc.relationshipType == ManagedRelationshipType.belongsTo) {
            var innerMatcherObject = innerMatcher as ManagedObject;
            var nestedMatcherPrimaryKeyMatcher = innerMatcherObject.backingMap[innerMatcherObject.entity.primaryKey];
            if (innerMatcherObject.backingMap.length == 1 && nestedMatcherPrimaryKeyMatcher != null) {
              return [
                new PropertyExpression(this, desc, nestedMatcherPrimaryKeyMatcher,
                    additionalVariablePrefix: prefix)
              ];
            }
          }

          bool disambiguate = true;
          RowMapper innerRowMapper = returningOrderedMappers
              .where((m) => m is RowMapper)
              .firstWhere(
                  (m) => (m as RowMapper).representsRelationship(desc),
                  orElse: () => null);

          if (innerRowMapper == null) {
            innerRowMapper =
                new RowMapper.implicit(PersistentJoinType.leftOuter, desc);
            innerRowMapper.originatingTable = this;
            createdImplicitRowMappers.add(innerRowMapper);
            disambiguate = false;
          }

          if (innerMatcher is ManagedSet) {
            innerMatcher = (innerMatcher as ManagedSet).matchOn;
          }

          return innerRowMapper.propertyExpressionsFromObject(
              innerMatcher, createdImplicitRowMappers,
              disambiguateVariableNames: disambiguate);
        })
        .expand((expressions) => expressions)
        .toList();
  }
}
