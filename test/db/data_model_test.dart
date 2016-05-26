import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Delete rule of setNull throws exception if property is not nullable", () {
    var successful = false;
    try {
      var _ = new DataModel(new DefaultPersistentStore(), [GenObj, GenNotNullable]);

      successful = true;
    } catch (e) {
      expect(e.message, "Relationship ref on _GenNotNullable set to nullify on delete, but is not nullable");
    }
    expect(successful, false);
  });
}

class GenObj extends Model<_GenObj> implements _GenObj {}
class _GenObj {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.hasOne, "ref")
  GenNotNullable gen;
}

class GenNotNullable extends Model<_GenNotNullable> implements _GenNotNullable {}
class _GenNotNullable {
  @primaryKey
  int id;

  @RelationshipAttribute(RelationshipType.belongsTo, "gen", deleteRule: RelationshipDeleteRule.nullify, required: false)
  GenObj ref;
}
