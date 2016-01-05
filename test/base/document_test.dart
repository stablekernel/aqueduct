import 'package:test/test.dart';
import 'package:monadart/monadart.dart';
import 'dart:mirrors';
import 'dart:async';
import 'package:analyzer/analyzer.dart';
import 'dart:convert';
import 'dart:io';

main() {
  test("Package resolver", () {
    String homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    var p = new PackagePathResolver(new File(".packages").path);
    var resolvedPath = p.resolve(new Uri(scheme: "package", path: "analyzer/file_system/file_system.dart"));

    expect(resolvedPath.endsWith("file_system/file_system.dart"), true);
    expect(resolvedPath.startsWith("$homeDir/.pub-cache/hosted/pub.dartlang.org"), true);
  });

  test("Documentation test", () {
    var t = new TController();
//    print("${t.document().asMap()}");


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
    router.route("/t").then(new RequestHandlerGenerator<TController>());
  }
}

///
/// Documentation
///
class TController extends HttpController {
  /// ABCD
  /// EFGH
  /// IJKL
  @httpGet getAll() async {
    return new Response.ok("");
  }
  /// ABCD
  @httpPut putOne(int id) async {
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
