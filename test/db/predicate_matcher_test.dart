import 'package:monadart/monadart.dart';
import 'package:test/test.dart';

main() {
  test("Assignment matcher", () {
    var matcher = new TestModelMatcher();
    matcher.id = "foo";
    var tm = new TestModelBacking();
    tm.id = "fo";

  });
}

@proxy @ModelBacking(TestModelBacking)
class TestModel extends Model implements TestModelBacking {

}

class TestModelBacking {
  @Attributes(primaryKey: true, databaseType: "bigserial")
  int id;

  String name;

  DateTime dateCreatedAt;
}