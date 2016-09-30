import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';
import '../helpers.dart';
import 'dart:convert';

main() {
  test("Package resolver", () {
    String homeDir = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    var p = new PackagePathResolver(new File(".packages").path);
    var resolvedPath = p.resolve(new Uri(scheme: "package", path: "analyzer/file_system/file_system.dart"));

    expect(resolvedPath.endsWith("file_system/file_system.dart"), true);
    expect(resolvedPath.startsWith("$homeDir/.pub-cache/hosted/pub.dartlang.org"), true);
  });

  group("Happy path", () {
    var app = new Application<TestSink>();
    var apiDocs = app.document(new PackagePathResolver(new File(".packages").path)).asMap();

    print("${JSON.encode(apiDocs)}");

    test("Document has appropriate metadata", () {
      expect(apiDocs["openapi"], contains("3.0"));
      expect(apiDocs["info"], contains("title"));
      expect(apiDocs["info"], contains("description"));
      expect(apiDocs["info"], contains("version"));
      expect(apiDocs["info"], contains("termsOfService"));
      expect(apiDocs["info"], contains("contact"));
      expect(apiDocs["info"], contains("license"));

      expect(apiDocs["host"], []);
      expect(apiDocs["security"], []);
    });

    test("Document has appropriate content types at top-level", () {
      expect(apiDocs["consumes"], contains("application/json; charset=utf-8"));
      expect(apiDocs["consumes"], contains("application/x-www-form-urlencoded"));
      expect(apiDocs["produces"], contains("application/json; charset=utf-8"));
    });

    test("Document provides all security schemes", () {
      var secDefs = apiDocs["securityDefinitions"] as Map<String, Map<String, dynamic>>;
      expect(secDefs.length, 3);
      //expect(secDefs["oauth2.application"], )
    });


  });

}

class TestSink extends RequestSink implements AuthenticationServerDelegate<TestUser, Token, AuthCode> {
  TestSink(Map<String, dynamic> opts) : super(opts) {
    authServer = new AuthenticationServer<TestUser, Token, AuthCode>(this);
  }

  AuthenticationServer<TestUser, Token, AuthCode> authServer;

  void addRoutes() {
    router.route("/auth/code").pipe(authServer.newAuthenticator(strategy: AuthenticationStrategy.Client)).generate(() => new AuthCodeController(authServer));
    router.route("/auth/token").pipe(authServer.newAuthenticator(strategy: AuthenticationStrategy.Client)).generate(() => new AuthController(authServer));
    router.route("/t[/:id[/:notID]]").pipe(authServer.newAuthenticator()).generate(() => new TController());
  }

  Future<Token> tokenForAccessToken(AuthenticationServer server, String accessToken) => null;
  Future<Token> tokenForRefreshToken(AuthenticationServer server, String refreshToken) => null;
  Future<TestUser> authenticatableForUsername(AuthenticationServer server, String username) => null;
  Future<TestUser> authenticatableForID(AuthenticationServer server, dynamic id) => null;
  Future<Client> clientForID(AuthenticationServer server, String id) => null;
  Future deleteTokenForRefreshToken(AuthenticationServer server, String refreshToken) => null;
  Future<Token> storeToken(AuthenticationServer server, dynamic t) => null;
  Future updateToken(AuthenticationServer server, dynamic t) => null;
  Future<AuthCode> storeAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future updateAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future deleteAuthCode(AuthenticationServer server, dynamic ac) => null;
  Future<AuthCode> authCodeForCode(AuthenticationServer server, String code) => null;

  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) {
    return authServer.documentSecuritySchemes(resolver);
  }
}

/* DON'T CHANGE WHITESPACE BLOCK */

///
/// Documentation
///
class TController extends HTTPController {
  /// ABCD
  /// EFGH
  /// IJKL
  @httpGet getAll({@HTTPQuery("param") String param: null}) async {
    return new Response.ok("");
  }
  /// ABCD
  @httpPut putOne(@HTTPPath("id") int id, {@HTTPQuery("p1") int p1: null, @HTTPHeader("X-P2") int p2: null}) async {
    return new Response.ok("");
  }
  @httpGet getOne(@HTTPPath("id") int id) async {
    return new Response.ok("");
  }

  /// MNOP
  /// QRST

  @httpGet getTwo(@HTTPPath("id") int id, @HTTPPath("notID") int notID) async {
    return new Response.ok("");
  }
  /// EFGH
  /// IJKL
  @httpPost

  Future<Response> createOne() async {
    return new Response.ok("");
  }
}

/* END DON'T CHANGE WHITESPACE BLOCK */
