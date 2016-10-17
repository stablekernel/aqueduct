import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';
import '../helpers.dart';

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

    test("Document has appropriate metadata", () {
      expect(apiDocs["swagger"], contains("2.0"));
      expect(apiDocs["info"], contains("title"));
      expect(apiDocs["info"], contains("description"));
      expect(apiDocs["info"], contains("version"));
      expect(apiDocs["info"], contains("termsOfService"));
      expect(apiDocs["info"], contains("contact"));
      expect(apiDocs["info"], contains("license"));

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

      expect(secDefs["oauth2.application"], {
        "type" : "oauth2",
        "description" : isNotNull,
        "flow" : "application",
        "tokenUrl" : "http://localhost/auth/token",
        "scopes" : isNotNull
      });

      expect(secDefs["oauth2.password"], {
        "type" : "oauth2",
        "description" : isNotNull,
        "flow" : "password",
        "tokenUrl" : "http://localhost/auth/token",
        "scopes" : isNotNull
      });

      expect(secDefs["oauth2.accessCode"], {
        "type" : "oauth2",
        "description" : isNotNull,
        "flow" : "accessCode",
        "authorizationUrl" : "http://localhost/auth/code",
        "tokenUrl" : "http://localhost/auth/token",
        "scopes" : isNotNull
      });
    });

    test("Paths", () {
      var paths = apiDocs["paths"] as Map<String, Map<String, dynamic>>;
      expect(paths.length, 5);
      expect(paths.keys.contains("/auth/code"), true);
      expect(paths.keys.contains("/auth/token"), true);
      expect(paths.keys.contains("/t"), true);
      expect(paths.keys.contains("/t/{id}"), true);
      expect(paths.keys.contains("/t/{id}/{notID}"), true);
    });

    test("Operations /t", () {
      var ops = apiDocs["paths"]["/t"] as Map<String, dynamic>;
      expect(ops.length, 3);
      expect(ops["parameters"], []);
      expect(ops["get"], {
        "summary": "ABCD",
        "description": "EFGH\nIJKL",
        "id": "TController.getAll",
        "deprecated": false,
        "tags": [],
        "consumes": [
          "application/json; charset=utf-8",
          "application/x-www-form-urlencoded"
        ],
        "produces": [
          "application/json; charset=utf-8"
        ],
        "parameters": [
          {
            "name": "param",
            "description": "",
            "required": false,
            "deprecated": false,
            "schema": {
              "type": "string",
              "required": true,
              "readOnly": false,
              "deprecated": false
            },
            "in": "query"
          }
        ],
        "responses": {
          "500": {
            "description": "Something went wrong",
            "schema": {
              "type": "object",
              "required": true,
              "readOnly": false,
              "deprecated": false,
              "properties": {
                "error": {
                  "type": "string",
                  "required": true,
                  "readOnly": false,
                  "deprecated": false
                }
              }
            },
            "headers": {}
          }
        },
        "security": [
          {
            "oauth2.password": []
          }
        ]
      });

      expect(ops["post"], {
        "summary": "EFGH",
        "description": "IJKL",
        "id": "TController.createOne",
        "deprecated": false,
        "tags": [],
        "consumes": [
          "application/json; charset=utf-8",
          "application/x-www-form-urlencoded"
        ],
        "produces": [
          "application/json; charset=utf-8"
        ],
        "parameters": [{
          "name": "X-Date",
          "description": "",
          "required": true,
          "deprecated": false,
          "schema": {
            "type": "string",
            "required": true,
            "readOnly": false,
            "deprecated": false,
            "format" : "date-time"
          },
          "in": "header"
        },{
          "name": "foo",
          "description": "",
          "required": true,
          "deprecated": false,
          "schema": {
            "type": "string",
            "required": true,
            "readOnly": false,
            "deprecated": false
          },
          "in": "formData"
        }],
        "responses": {
          "500": {
            "description": "Something went wrong",
            "schema": {
              "type": "object",
              "required": true,
              "readOnly": false,
              "deprecated": false,
              "properties": {
                "error": {
                  "type": "string",
                  "required": true,
                  "readOnly": false,
                  "deprecated": false
                }
              }
            },
            "headers": {}
          },
          "400": {
            "description": "Missing required query and/or header parameter(s).",
            "schema": {
              "type": "object",
              "required": true,
              "readOnly": false,
              "deprecated": false,
              "properties": {
                "error": {
                  "type": "string",
                  "required": true,
                  "readOnly": false,
                  "deprecated": false
                }
              }
            },
            "headers": {}
          }
        },
        "security": [
          {
            "oauth2.password": []
          }
        ]
      });
    });

    test("Operations /t/:id", () {
      var ops = apiDocs["paths"]["/t/{id}"] as Map<String, dynamic>;
      expect(ops, {
        "parameters" : [{
          'name': 'id',
          'description': '',
          'required': true,
          'deprecated': false,
          'schema': {
            'type': 'integer',
            'required': true,
            'readOnly': false,
            'deprecated': false,
            'format': 'int32'
          },
          'in': 'path'
        }],
        "put": {
          "summary": "ABCD",
          "description": "",
          "id": "TController.putOne",
          "deprecated": false,
          "tags": [],
          "consumes": [
            "application/json; charset=utf-8",
            "application/x-www-form-urlencoded"
          ],
          "produces": [
            "application/json; charset=utf-8"
          ],
          "parameters": [
            {
              "name": "p1",
              "description": "",
              "required": false,
              "deprecated": false,
              "schema": {
                "type": "integer",
                "required": true,
                "readOnly": false,
                "deprecated": false,
                "format": "int32"
              },
              "in": "query"
            },
            {
              "name": "X-P2",
              "description": "",
              "required": false,
              "deprecated": false,
              "schema": {
                "type": "integer",
                "required": true,
                "readOnly": false,
                "deprecated": false,
                "format": "int32"
              },
              "in": "header"
            }
          ],
          "responses": {
            "500": {
              "description": "Something went wrong",
              "schema": {
                "type": "object",
                "required": true,
                "readOnly": false,
                "deprecated": false,
                "properties": {
                  "error": {
                    "type": "string",
                    "required": true,
                    "readOnly": false,
                    "deprecated": false
                  }
                }
              },
              "headers": {}
            }
          },
          "security": [
            {
              "oauth2.password": []
            }
          ]
        },
        "get": {
          "summary": "",
          "description": "",
          "id": "TController.getOne",
          "deprecated": false,
          "tags": [],
          "consumes": [
            "application/json; charset=utf-8",
            "application/x-www-form-urlencoded"
          ],
          "produces": [
            "application/json; charset=utf-8"
          ],
          "parameters": [],
          "responses": {
            "500": {
              "description": "Something went wrong",
              "schema": {
                "type": "object",
                "required": true,
                "readOnly": false,
                "deprecated": false,
                "properties": {
                  "error": {
                    "type": "string",
                    "required": true,
                    "readOnly": false,
                    "deprecated": false
                  }
                }
              },
              "headers": {}
            }
          },
          "security": [
            {
              "oauth2.password": []
            }
          ]
        }
      });
    });

    test("Operation t/:id/:notID", () {
      expect(apiDocs["paths"]["/t/{id}/{notID}"]["parameters"], [{
        "name": "id",
        "description": "",
        "required": true,
        "deprecated": false,
        "schema": {
          "type": "integer",
          "required": true,
          "readOnly": false,
          "deprecated": false, "format": "int32"
        },
        "in": "path"}, {
          "name": "notID",
          "description": "",
          "required": true,
          "deprecated": false,
          "schema": {
            "type": "integer",
            "required": true,
            "readOnly": false,
            "deprecated": false,
            "format": "int32"
          },
        "in": "path"
      }]);

      expect(apiDocs["paths"]["/t/{id}/{notID}"]["get"], {
        "summary": "MNOP",
        "description": "QRST",
        "id": "TController.getTwo",
        "deprecated": false,
        "tags": [],
        "consumes": [
          "application/json; charset=utf-8",
          "application/x-www-form-urlencoded"
        ],
        "produces": [
          "application/json; charset=utf-8"
        ],
        "parameters": [],
        "responses": {
          "500": {
            "description": "Something went wrong",
            "schema": {
              "type": "object",
              "required": true,
              "readOnly": false,
              "deprecated": false,
              "properties": {
                "error": {
                  "type": "string",
                  "required": true,
                  "readOnly": false,
                  "deprecated": false
                }
              }
            },
            "headers": {}
          }
        },
        "security": [
          {
            "oauth2.password": []
          }
        ]
      });
    });
  });

}

class TestSink extends RequestSink implements AuthServerDelegate<TestUser, Token, AuthCode> {
  TestSink(Map<String, dynamic> opts) : super(opts) {
    authServer = new AuthServer<TestUser, Token, AuthCode>(this);
  }

  AuthServer<TestUser, Token, AuthCode> authServer;

  void addRoutes() {
    router.route("/auth/code").pipe(new Authenticator(authServer, strategy: AuthenticationStrategy.client)).generate(() => new AuthCodeController(authServer));
    router.route("/auth/token").pipe(new Authenticator(authServer, strategy: AuthenticationStrategy.client)).generate(() => new AuthController(authServer));
    router.route("/t[/:id[/:notID]]").pipe(new Authenticator(authServer)).generate(() => new TController());
  }

  Future<Token> tokenForAccessToken(AuthServer server, String accessToken) => null;
  Future<Token> tokenForRefreshToken(AuthServer server, String refreshToken) => null;
  Future<TestUser> authenticatableForUsername(AuthServer server, String username) => null;
  Future<TestUser> authenticatableForID(AuthServer server, dynamic id) => null;
  Future<AuthClient> clientForID(AuthServer server, String id) => null;
  Future deleteTokenForRefreshToken(AuthServer server, String refreshToken) => null;
  Future<Token> storeToken(AuthServer server, dynamic t) => null;
  Future updateToken(AuthServer server, dynamic t) => null;
  Future<AuthCode> storeAuthCode(AuthServer server, dynamic ac) => null;
  Future updateAuthCode(AuthServer server, dynamic ac) => null;
  Future deleteAuthCode(AuthServer server, dynamic ac) => null;
  Future<AuthCode> authCodeForCode(AuthServer server, String code) => null;

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

  Future<Response> createOne(@HTTPHeader("X-Date") DateTime date, @HTTPQuery("foo") String foo) async {
    return new Response.ok("");
  }
}

/* END DON'T CHANGE WHITESPACE BLOCK */
