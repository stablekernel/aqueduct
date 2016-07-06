import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';

main() {
  test("Package resolver", () {
    String homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    var p = new PackagePathResolver(new File(".packages").path);
    var resolvedPath = p.resolve(new Uri(scheme: "package", path: "analyzer/file_system/file_system.dart"));

    expect(resolvedPath.endsWith("file_system/file_system.dart"), true);
    expect(resolvedPath.startsWith("$homeDir/.pub-cache/hosted/pub.dartlang.org"), true);
  });

  test("App-to-router test", () {
    var app = new Application<TPipeline>();
    var doc = app.document(new PackagePathResolver(new File(".packages").path));
    print("${JSON.encode(doc.asMap())}");

  });

  test("Tests", () {
//    ApplicationPipeline pipeline = new TPipeline({});
//    pipeline.addRoutes();
//
//    var docs = pipeline.document();
//    var document = new APIDocument()
//      ..items = docs;

  });

}

class TPipeline extends ApplicationPipeline {
  TPipeline(Map opts) : super(opts);

  void addRoutes() {
    router.route("/t[/:id[/:notID]]").next(() => new TController());
  }
}

///
/// Documentation
///
class TController extends HTTPController {
  /// ABCD
  /// EFGH
  /// IJKL
  @httpGet getAll({String param: null}) async {
    return new Response.ok("");
  }
  /// ABCD
  @httpPut putOne(int id, {int p1: null, int p2: null}) async {
    return new Response.ok("");
  }
  @httpGet getOne(int id) async {
    return new Response.ok("");
  }

  /// MNOP
  /// QRST

  @httpGet getTwo(int id, int notID) async {
    return new Response.ok("");
  }
  /// EFGH
  /// IJKL
  @httpPost

  Future<Response> createOne() async {
    return new Response.ok("");
  }
}
