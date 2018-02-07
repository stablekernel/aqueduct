import '../db.dart';
import 'package:aqueduct/src/db/postgresql/mappers/table.dart';
import 'package:aqueduct/src/db/postgresql/mappers/expression.dart';
import 'package:aqueduct/src/db/postgresql/mappers/column.dart';
import 'package:aqueduct/src/db/postgresql/mappers/row.dart';
import 'package:aqueduct/src/db/managed/relationship_type.dart';

abstract class PredicateBuilder implements EntityTableMapper {
  @override
  ManagedEntity get entity;

  List<ExpressionMapper> propertyExpressionsFromObject(
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
              new ExpressionMapper(
                  this, desc, innerMatcher, additionalVariablePrefix: prefix)
            ];
          }

          // But if it is a relationship and only the primary key value is set, then we can do t
          // this without the join.. its just the foreign key column
          var relationshipDesc = desc as ManagedRelationshipDescription;
          if (relationshipDesc.relationshipType ==
              ManagedRelationshipType.belongsTo) {
            var innerMatcherObject = innerMatcher as ManagedObject;
            var nestedMatcherPrimaryKeyMatcher = innerMatcherObject
                .backingMap[innerMatcherObject.entity.primaryKey];
            if (innerMatcherObject.backingMap.length == 1 &&
                nestedMatcherPrimaryKeyMatcher != null) {
              return [
                new ExpressionMapper(
                    this, desc, nestedMatcherPrimaryKeyMatcher,
                    additionalVariablePrefix: prefix)
              ];
            }
          }

          bool disambiguate = true;
          RowMapper innerRowMapper = returningOrderedMappers
              .where((m) => m is RowMapper)
              .firstWhere((m) => (m as RowMapper).representsRelationship(desc),
                  orElse: () => null);

          if (innerRowMapper == null) {
            innerRowMapper =
                new RowMapper.implicit(PersistentJoinType.leftOuter, desc);
            innerRowMapper.originatingTable = this;
            createdImplicitRowMappers.add(innerRowMapper);
            disambiguate = false;
          }

          if (innerMatcher is ManagedSet) {
            innerMatcher = (innerMatcher as ManagedSet).haveAtLeastOneWhere;
          }

          return innerRowMapper.propertyExpressionsFromObject(
              innerMatcher, createdImplicitRowMappers,
              disambiguateVariableNames: disambiguate);
        })
        .expand((expressions) => expressions)
        .toList();
  }
}
