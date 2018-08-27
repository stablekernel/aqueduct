import 'dart:io';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();
  APIDocumentContext ctx;
  setUp(() {
    ctx = APIDocumentContext(APIDocument()
      ..info = APIInfo("x", "1.0.0")
      ..paths = {}
      ..components = APIComponents());
  });

  tearDown(() async {
    // Just in case the test didn't clear these
    await ctx.finalize();
  });

  test("Try to decode non-serializable throws error", () async {
    try {
      Serializable.document(ctx, String);
      fail("unreachable");
      // ignore: empty_catches
    } on ArgumentError {}
  });

  test("Serializable contains properties for each declared field", () async {
    final doc = Serializable.document(ctx, A);
    await ctx.finalize();

    expect(doc.properties.length, 2);
    expect(doc.title, isEmpty);
    expect(doc.description, isEmpty);

    expect(doc.properties["x"].type, APIType.integer);
    expect(doc.properties["x"].title, "x");
    expect(doc.properties["x"].description, contains("yz"));

    expect(doc.properties["b"].type, APIType.object);
    expect(doc.properties["b"].title, "bvar");
    expect(doc.properties["b"].description, isEmpty);
  });

  test("Nested serializable is documented", () async {
    final doc = Serializable.document(ctx, A);
    expect(doc.properties["b"].properties.length, 1);
    expect(doc.properties["b"].properties["y"].type, APIType.string);
  });

  test("Types with documentation comments are documented", () async {
    final doc = Serializable.document(ctx, B);
    await ctx.finalize();

    expect(doc.title, "b");
    expect(doc.description, isEmpty);
  });

  test(
      "If Serializable cannot be documented, it still allows doc generation but shows error in document",
      () async {
    final doc = Serializable.document(ctx, FailsToDocument);
    await ctx.finalize();

    expect(doc.title, contains("Failed to auto"));
    expect(doc.title, contains("FailsToDocument"));
    expect(doc.description, contains("HttpServer"));
    expect(doc.additionalPropertyPolicy,
        APISchemaAdditionalPropertyPolicy.freeForm);
  });

  test("Serializable can override static document method", () async {
    final doc = Serializable.document(ctx, OverrideDocument);
    await ctx.finalize();

    expect(doc.properties["k"], isNotNull);
  });
}

class A extends Serializable {
  /// x
  ///
  /// yz
  int x;

  /// bvar
  B b;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

/// b
class B extends Serializable {
  String y;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

class FailsToDocument extends Serializable {
  HttpServer nonsenseProperty;

  @override
  Map<String, dynamic> asMap() => null;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}
}

class OverrideDocument extends Serializable {
  static APISchemaObject document(
      APIDocumentContext context, Type serializable) {
    return APISchemaObject.object({"k": APISchemaObject.string()});
  }

  @override
  Map<String, dynamic> asMap() => null;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {}
}
