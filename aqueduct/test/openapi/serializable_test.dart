import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();
  APIDocumentContext ctx;
  setUp(() {
    ctx = new APIDocumentContext(new APIDocument()
      ..info = new APIInfo("x", "1.0.0")
      ..paths = {}
      ..components = new APIComponents());
  });

  tearDown(() async {
    // Just in case the test didn't clear these
    await ctx.finalize();
  });

  test("Try to decode non-serializable throws error", () async {
    try {
      HTTPSerializable.document(ctx, String);
      fail("unreachable");
    } on ArgumentError {}
  });

  test("Serializable contains properties for each declared field", () async {
    final doc = HTTPSerializable.document(ctx, A);
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
    final doc = HTTPSerializable.document(ctx, A);
    expect(doc.properties["b"].properties.length, 1);
    expect(doc.properties["b"].properties["y"].type, APIType.string);
  });

  test("Types with documentation comments are documented", () async {
    final doc = HTTPSerializable.document(ctx, B);
    await ctx.finalize();

    expect(doc.title, "b");
    expect(doc.description, isEmpty);
  });
}

class A extends HTTPSerializable {
  /// x
  ///
  /// yz
  int x;
  /// bvar
  B b;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {

  }

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}

/// b
class B extends HTTPSerializable {
  String y;

  @override
  void readFromMap(Map<String, dynamic> requestBody) {

  }

  @override
  Map<String, dynamic> asMap() {
    return null;
  }
}