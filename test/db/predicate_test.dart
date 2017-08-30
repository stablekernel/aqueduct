import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("QueryPredicate throws error if 'and' predicates have duplicate keys", () {
    var p1 = new QueryPredicate("p=@p", {"p": 1});
    var p2 = new QueryPredicate("p=@p", {"p": 2});
    try {
      QueryPredicate.andPredicates([p1, p2]);
      fail("should fail");
    } on QueryPredicateException catch (e) {
      expect(e.message, contains("Duplicate keys"));
    }
  });
}