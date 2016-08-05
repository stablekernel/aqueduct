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
}

class TPipeline extends ApplicationPipeline implements AuthenticationServerDelegate {
  TPipeline(Map opts) : super(opts) {
    authServer = new AuthenticationServer(this);
  }

  AuthenticationServer authServer;

  void addRoutes() {
    router.route("/t[/:id[/:notID]]").next(authServer.authenticator()).next(() => new TController());
  }

  Future<dynamic> tokenForAccessToken(AuthenticationServer server, String accessToken) => null;
  Future<dynamic> tokenForRefreshToken(AuthenticationServer server, String refreshToken) => null;
  Future<dynamic> authenticatableForUsername(AuthenticationServer server, String username) => null;
  Future<dynamic> authenticatableForID(AuthenticationServer server, dynamic id) => null;
  Future<Client> clientForID(AuthenticationServer server, String id) => null;
  Future deleteTokenForRefreshToken(AuthenticationServer server, String refreshToken) => null;
  Future<dynamic> storeToken(AuthenticationServer server, dynamic t) => null;
  Future updateToken(AuthenticationServer server, dynamic t) => null;
  Future<dynamic> storeAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future updateAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future deleteAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future<dynamic> authCodeForCode(AuthenticationServer server, String code) => null;

  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) {
    return authServer.documentSecuritySchemes(resolver);
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
