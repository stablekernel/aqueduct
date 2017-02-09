import 'package:aqueduct/aqueduct.dart';
import 'package:test/test.dart';

void main() {
  test("Cannot create invalid scopes", () {
    try {
      new AuthScope("");
      expect(true, false);
    } on FormatException {}

    try {
      new AuthScope(null);
      expect(true, false);
    } on FormatException {}

    try {
      new AuthScope("user.readonly:location");
      expect(true, false);
    } on FormatException {}

    try {
      new AuthScope("user:location.readonly:equipment");
      expect(true, false);
    } on FormatException {}

    try {
      new AuthScope("user:location:");
      expect(true, false);
    } on FormatException {}

    try {
      new AuthScope(":user:location:");
      expect(true, false);
    } on FormatException {}
  });

  // Success allows

  test("Single element equal scopes match", () {
    var scope = new AuthScope("user");
    expect(scope.allows("user"), true);
    expect(scope.isExactly("user"), true);
  });

  test("Single element with modifier equal scopes match", () {
    var scope = new AuthScope("user.readonly");
    expect(scope.allows("user.readonly"), true);
    expect(scope.isExactly("user.readonly"), true);
  });

  test("Single element scope with modifier allows scope without", () {
    var scope = new AuthScope("user.readonly");
    expect(scope.allows("user"), true);
  });

  test("Multiple element equal scopes match", () {
    var scope = new AuthScope("user:location:equipment");
    expect(scope.allows("user:location:equipment"), true);
    expect(scope.isExactly("user:location:equipment"), true);
  });

  test("Multiple element equal scopes match", () {
    var scope = new AuthScope("user:location:equipment.readonly");
    expect(scope.allows("user:location:equipment.readonly"), true);
    expect(scope.isExactly("user:location:equipment.readonly"), true);
  });

  test("Multiple element scope with modifier allows scope without", () {
    var scope = new AuthScope("user:location:equipment.readonly");
    expect(scope.allows("user:location:equipment"), true);
  });

  test("Multiple element scope allows less restrictive scope", () {
    var scope = new AuthScope("user:location:equipment");
    expect(scope.allows("user:location"), true);
  });

  test("Very restrictive scope allows root scope", () {
    var scope = new AuthScope("user:location:equipment:blah:de:blah");
    expect(scope.allows("user"), true);
    expect(scope.allows("user:location"), true);
    expect(scope.allows("user:location:equipment"), true);
  });

  // Failures
  test("Single element scopes with different roots fail", () {
    var scope = new AuthScope("user");
    expect(scope.allows("notuser"), false);
  });

  test("Single element scopes with different modifiers fail", () {
    var scope = new AuthScope("user.readonly");
    expect(scope.allows("user.actions"), false);
  });

  test("Single element scope without modifier does not allow one with", () {
    var scope = new AuthScope("user");
    expect(scope.allows("user.readonly"), false);
  });

  test(
      "Single element scope does not allow more restrictive multiple element scope",
      () {
    var scope = new AuthScope("user");
    expect(scope.allows("user:location"), false);
  });

  test(
      "Single element scope with modifier does not allow more restrictive multiple element scope even though it has same modifier",
      () {
    var scope = new AuthScope("user.readonly");
    expect(scope.allows("user:location.readonly"), false);
  });

  test(
      "Multiple element scope does not allow multiple element, even if root is same",
      () {
    var scope = new AuthScope("user:location");
    expect(scope.allows("user:posts"), false);
  });

  test(
      "Multiple element scope does not allow modifier restricted, even though elements are the same",
      () {
    var scope = new AuthScope("user:location");
    expect(scope.allows("user:location.readonly"), false);
  });

  test(
      "Multiple element scope does not allow different modifier, even though elements are the same",
      () {
    var scope = new AuthScope("user:location.something");
    expect(scope.allows("user:location.readonly"), false);
  });

  test("Multiple element scope that does not allow more restrictive scope", () {
    var scope = new AuthScope("user:location");
    expect(scope.allows("user:location:equipment"), false);
  });
}
