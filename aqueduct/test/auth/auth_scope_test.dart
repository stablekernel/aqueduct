import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot create invalid scopes", () {
    try {
      AuthScope("");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope(null);
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope("user.readonly:location");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope("user:location.readonly:equipment");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope("user:location:");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope(":user:location:");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope(" ab");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}

    try {
      AuthScope("ab c");
      expect(true, false);
      // ignore: empty_catches
    } on FormatException {}
  });

  // Success allows

  test("Single element equal scopes match", () {
    var scope = AuthScope("user");
    expect(scope.allows("user"), true);
    expect(scope.isExactly("user"), true);
  });

  test("Single element with modifier equal scopes match", () {
    var scope = AuthScope("user.readonly");
    expect(scope.allows("user.readonly"), true);
    expect(scope.isExactly("user.readonly"), true);
  });

  test("Single element scope with modifier allows scope without", () {
    var scope = AuthScope("user.readonly");
    expect(scope.allows("user"), true);
  });

  test("Multiple element equal scopes match", () {
    var scope = AuthScope("user:location:equipment");
    expect(scope.allows("user:location:equipment"), true);
    expect(scope.isExactly("user:location:equipment"), true);
  });

  test("Multiple element equal scopes match, with modifier", () {
    var scope = AuthScope("user:location:equipment.readonly");
    expect(scope.allows("user:location:equipment.readonly"), true);
    expect(scope.isExactly("user:location:equipment.readonly"), true);
  });

  test("Multiple element scope with modifier allows scope without", () {
    var scope = AuthScope("user:location:equipment.readonly");
    expect(scope.allows("user:location:equipment"), true);
  });

  test("Multiple element scope allows less restrictive scope", () {
    var scope = AuthScope("user:location:equipment");
    expect(scope.allows("user:location"), true);
  });

  test("Very restrictive scope allows root scope", () {
    var scope = AuthScope("user:location:equipment:blah:de:blah");
    expect(scope.allows("user"), true);
    expect(scope.allows("user:location"), true);
    expect(scope.allows("user:location:equipment"), true);
  });

  // Failures
  test("Single element scopes with different roots fail", () {
    var scope = AuthScope("user");
    expect(scope.allows("notuser"), false);
  });

  test("Single element scopes with different modifiers fail", () {
    var scope = AuthScope("user.readonly");
    expect(scope.allows("user.actions"), false);
  });

  test("Single element scope without modifier does not allow one with", () {
    var scope = AuthScope("user");
    expect(scope.allows("user.readonly"), false);
  });

  test(
      "Single element scope does not allow more restrictive multiple element scope",
      () {
    var scope = AuthScope("user");
    expect(scope.allows("user:location"), false);
  });

  test(
      "Single element scope with modifier does not allow more restrictive multiple element scope even though it has same modifier",
      () {
    var scope = AuthScope("user.readonly");
    expect(scope.allows("user:location.readonly"), false);
  });

  test(
      "Multiple element scope does not allow multiple element, even if root is same",
      () {
    var scope = AuthScope("user:location");
    expect(scope.allows("user:posts"), false);
  });

  test(
      "Multiple element scope does not allow modifier restricted, even though elements are the same",
      () {
    var scope = AuthScope("user:location");
    expect(scope.allows("user:location.readonly"), false);
  });

  test(
      "Multiple element scope does not allow different modifier, even though elements are the same",
      () {
    var scope = AuthScope("user:location.something");
    expect(scope.allows("user:location.readonly"), false);
  });

  test("Multiple element scope that does not allow more restrictive scope", () {
    var scope = AuthScope("user:location");
    expect(scope.allows("user:location:equipment"), false);
  });

  test("Can contain all valid characters", () {
    var scope = AuthScope(
        "ABC:DEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzz0123456789!#\$%&'`()*+,./;<=>?@[]^_{|}-");
    expect(
        scope.allows(
            "ABC:DEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzz0123456789!#\$%&'`()*+,./;<=>?@[]^_{|}-"),
        true);
    expect(scope.allows("ABC"), true);
  });

  test("Cannot contain invalid characters", () {
    try {
      var _ = AuthScope("abdef\"xz");
      expect(true, false);
    } on FormatException catch (e) {
      expect(e.toString(), contains("Invalid authorization scope"));
    }

    try {
      var _ = AuthScope("abdef\\xz");
      expect(true, false);
    } on FormatException catch (e) {
      expect(e.toString(), contains("Invalid authorization scope"));
    }
  });

  test("Verify isSubsetOrEqualTo", () {
    var scope = AuthScope("users:foo");
    expect(scope.isSubsetOrEqualTo(AuthScope("users")), true);
    expect(scope.isSubsetOrEqualTo(AuthScope("users:foo")), true);
    expect(scope.isSubsetOrEqualTo(AuthScope("users:foo.readonly")), false);
    expect(scope.isSubsetOrEqualTo(AuthScope("xyz")), false);
    expect(scope.isSubsetOrEqualTo(AuthScope("users:foo:bar")), false);
  });

  group("AuthScope.verify", () {
    test("Single scope that is fulfilled by exact match", () {
      final requiredScopes = ["scope"].map((s) => AuthScope(s)).toList();
      final providedScopes = ["scope"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), true);
    });

    test("Single scope that is not fulfilled by totally different scope", () {
      final requiredScopes = ["scope"].map((s) => AuthScope(s)).toList();
      final providedScopes = ["scope1"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), false);
    });

    test("Single scope that is not fulfilled subset", () {
      final requiredScopes = ["scope"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope:bar", "scope.readonly"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), false);
    });

    test("Single scope that is fulfilled by one of scope", () {
      final requiredScopes = ["scope"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope1", "scope"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), true);
    });

    test("Multiple scope that is fulfilled by exact matches", () {
      final requiredScopes =
          ["scope1", "scope2"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope1", "scope2"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), true);
    });

    test("Multiple scope that is fulfilled by exact matches, in diff order",
        () {
      final requiredScopes =
          ["scope1", "scope2"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope2", "scope1"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), true);
    });

    test("Multiple scope where only one is fulfilled is false", () {
      final requiredScopes =
          ["scope1", "scope2"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope2", "scope3"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), false);
    });

    test("Multiple scope where one scope is a subset is false", () {
      final requiredScopes =
          ["scope1", "scope2"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope2", "scope1:next"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), false);
    });

    test("Multiple scope that is fulfilled by superscopes", () {
      final requiredScopes =
          ["scope1:next", "scope2.readonly"].map((s) => AuthScope(s)).toList();
      final providedScopes =
          ["scope2", "scope1"].map((s) => AuthScope(s)).toList();
      expect(AuthScope.verify(requiredScopes, providedScopes), true);
    });

    test("Empty required always yields true", () {
      expect(
          AuthScope.verify(
              [], ["scope2", "scope1"].map((s) => AuthScope(s)).toList()),
          true);
      expect(AuthScope.verify([], ["scope1"].map((s) => AuthScope(s)).toList()),
          true);
      expect(AuthScope.verify([], <String>[].map((s) => AuthScope(s)).toList()),
          true);
    });

    test("Null required always yields true", () {
      expect(
          AuthScope.verify(
              null, ["scope2", "scope1"].map((s) => AuthScope(s)).toList()),
          true);
      expect(
          AuthScope.verify(null, ["scope1"].map((s) => AuthScope(s)).toList()),
          true);
      expect(
          AuthScope.verify(null, <String>[].map((s) => AuthScope(s)).toList()),
          true);
    });
  });

  group("Client behavior", () {
    test("Client collapses redundant scope because of nesting", () {
      var c = AuthClient("a", "b", "c",
          allowedScopes: [AuthScope("abc"), AuthScope("abc:def")]);
      expect(c.allowedScopes.length, 1);
      expect(c.allowedScopes.first.isExactly("abc"), true);

      c = AuthClient("a", "b", "c", allowedScopes: [
        AuthScope("abc"),
        AuthScope("abc:def"),
        AuthScope("abc:def:xyz"),
        AuthScope("cba"),
        AuthScope("cba:foo")
      ]);
      expect(c.allowedScopes.length, 2);
      expect(c.allowedScopes.any((s) => s.isExactly("abc")), true);
      expect(c.allowedScopes.any((s) => s.isExactly("cba")), true);
    });

    test("Client collapses redundant scope because of modifier", () {
      var c = AuthClient("a", "b", "c", allowedScopes: [
        AuthScope("abc"),
        AuthScope("abc:def"),
        AuthScope("abc.readonly"),
        AuthScope("abc:def.readonly")
      ]);
      expect(c.allowedScopes.length, 1);
      expect(c.allowedScopes.first.isExactly("abc"), true);

      c = AuthClient("a", "b", "c", allowedScopes: [
        AuthScope("abc"),
        AuthScope("abc:def"),
        AuthScope("abc:def:xyz.readonly"),
        AuthScope("cba"),
        AuthScope("cba:foo.readonly")
      ]);
      expect(c.allowedScopes.length, 2);
      expect(c.allowedScopes.any((s) => s.isExactly("abc")), true);
      expect(c.allowedScopes.any((s) => s.isExactly("cba")), true);
    });
  });
}
