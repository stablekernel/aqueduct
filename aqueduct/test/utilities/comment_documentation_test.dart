import 'package:aqueduct/src/utilities/documented_element.dart';
import 'package:aqueduct/src/utilities/documented_element_analyzer_bridge.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  DocumentedElement.provider = AnalyzerDocumentedElementProvider();
  DocumentedElement comments;

  setUpAll(() async {
    comments = await DocumentedElement.get(T);
  });

  test("Field comments can be accessed", () {
    expect(comments[#field].summary, "field");
  });

  test("Getter comments can be accessed", () {
    expect(comments[#getter].summary, "getter");
  });

  test("Setter comments can be accessed", () {
    expect(comments[#setter].summary, "setter");
  });

  test("Declaration with normal comment yields no comment", () {
    expect(comments[#normalComment].summary, "");
    expect(comments[#normalComment].description, "");
  });

  test("Declaration with no documentation yields no comment", () {
    expect(comments[#noDocs].summary, "");
    expect(comments[#noDocs].description, "");
  });

  test("Declaration with summary documentation yields summary only", () {
    final summary = comments[#summaryDocs];
    expect(summary.summary, "Just a summary.");
    expect(summary.description, "");
  });

  test("Declaration with full comment yields summary and description", () {
    final full = comments[#fullDocs];
    expect(full.summary, "A summary.");
    expect(full.description, "A description across multiple lines");
  });

  test("Can access cache", () async {
    final cached = await DocumentedElement.get(T);
    expect(cached.hashCode, comments.hashCode);
    expect(comments[#summaryDocs], isNotNull);
  });

  test("Can access comments from another package", () async {
    final c = await DocumentedElement.get(Request);
    expect(c.summary, contains("HTTP request"));
  });

  test("Can access method params", () {
    expect(comments[#args][#a].summary, "arg a");
    expect(comments[#args][#b].summary, "arg b");
  });
}

class T {
  T();
  T.foo();

  /// field
  String field;

  /// getter
  String get getter {
    return "";
  }

  /// setter
  set setter(String s) {}

  // A normal comment
  void normalComment() {}

  void noDocs() {}

  /// Just a summary.
  void summaryDocs() {}

  /// A summary.
  ///
  /// A description across
  /// multiple
  /// lines
  void fullDocs(String a, {String b}) {}

  void args(

      /// arg a
      String a,
      {

      /// arg b
      String b}) {}
}
