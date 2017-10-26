import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';
import 'dart:async';
import 'dart:io';
import '../helpers.dart';

void main() {
  test("Package resolver", () {
    String homeDir =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    var p = new PackagePathResolver(new File(".packages").path);
    var resolvedPath = p.resolve(new Uri(
        scheme: "package", path: "analyzer/file_system/file_system.dart"));

    expect(resolvedPath.endsWith("file_system/file_system.dart"), true);
    expect(
        resolvedPath.startsWith("$homeDir/.pub-cache/hosted/pub.dartlang.org"),
        true);
  });

  group("Happy path", () {
    var resolver = new PackagePathResolver(new File(".packages").path);
    Map<String, dynamic> apiDocs;

    setUp(() async {
      apiDocs = (await Application.document(
              TestSink, new ApplicationConfiguration(), resolver))
          .asMap();
    });

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
      expect(
          apiDocs["consumes"], contains("application/x-www-form-urlencoded"));
      expect(apiDocs["produces"], contains("application/json; charset=utf-8"));
    });

    test("Document provides all security schemes", () {
      var secDefs =
          apiDocs["securityDefinitions"] as Map<String, Map<String, dynamic>>;
      expect(secDefs.length, 3);

      expect(secDefs["basic.clientAuth"], {
        "type": "basic",
        "description": isNotNull,
      });

      expect(secDefs["oauth2.password"], {
        "type": "oauth2",
        "description": isNotNull,
        "flow": "password",
        "tokenUrl": "http://localhost/auth/token"
      });

      expect(secDefs["oauth2.accessCode"], {
        "type": "oauth2",
        "description": isNotNull,
        "flow": "accessCode",
        "authorizationUrl": "http://localhost/auth/code",
        "tokenUrl": "http://localhost/auth/token"
      });
    });

    test("Paths", () {
      var paths = apiDocs["paths"] as Map<String, Map<String, dynamic>>;
      expect(paths.length, 7);
      expect(paths.keys.contains("/auth/code"), true);
      expect(paths.keys.contains("/auth/token"), true);
      expect(paths.keys.contains("/t"), true);
      expect(paths.keys.contains("/t/{id}"), true);
      expect(paths.keys.contains("/t/{id}/{notID}"), true);
      expect(paths.keys.contains("/h"), true);
      expect(paths.keys.contains("/h/{var}"), true);
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
        "produces": ["application/json; charset=utf-8"],
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
            }
          }
        },
        "security": [
          {"oauth2.accessCode": []},
          {"oauth2.password": []}
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
        "produces": ["application/json; charset=utf-8"],
        "parameters": [
          {
            "name": "X-Date",
            "description": "",
            "required": true,
            "deprecated": false,
            "schema": {
              "type": "string",
              "required": true,
              "readOnly": false,
              "deprecated": false,
              "format": "date-time"
            },
            "in": "header"
          },
          {
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
            }
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
            }
          }
        },
        "security": [
          {"oauth2.accessCode": []},
          {"oauth2.password": []}
        ]
      });
    });

    test("Operations /t/:id", () {
      var ops = apiDocs["paths"]["/t/{id}"] as Map<String, dynamic>;
      expect(ops, {
        "parameters": [
          {
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
          }
        ],
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
          "produces": ["application/json; charset=utf-8"],
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
              }
            }
          },
          "security": [
            {"oauth2.accessCode": []},
            {"oauth2.password": []}
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
          "produces": ["application/json; charset=utf-8"],
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
              }
            }
          },
          "security": [
            {"oauth2.accessCode": []},
            {"oauth2.password": []}
          ]
        }
      });
    });

    test("Operation t/:id/:notID", () {
      expect(apiDocs["paths"]["/t/{id}/{notID}"]["parameters"], [
        {
          "name": "id",
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
        },
        {
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
        }
      ]);

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
        "produces": ["application/json; charset=utf-8"],
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
            }
          }
        },
        "security": [
          {"oauth2.accessCode": []},
          {"oauth2.password": []}
        ]
      });
    });
  });
}

class TestSink extends RequestSink {
  AuthServer authServer;

  @override
  Future willOpen() async {
    authServer = new AuthServer(new InMemoryAuthStorage());
  }

  @override
  RequestController get entry {
    final router = new Router();
    router
        .route("/auth/code")
        .pipe(new Authorizer.basic(authServer))
        .generate(() => new AuthCodeController(authServer));
    router
        .route("/auth/token")
        .pipe(new Authorizer.basic(authServer))
        .generate(() => new AuthController(authServer));
    router
        .route("/t[/:id[/:notID]]")
        .pipe(new Authorizer.bearer(authServer))
        .generate(() => new TController());
    router.route("/h[/:var]").listen((Request req) async {
      return new Response.ok("");
    });
    return router;
  }

  @override
  Map<String, APISecurityScheme> documentSecuritySchemes(
      PackagePathResolver resolver) {
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
  @Bind.get()
  Future<Response> getAll({@Bind.query("param") String param}) async {
    return new Response.ok("");
  }

  /// ABCD
  @Bind.put()
  Future<Response> putOne(@Bind.path("id") int id,
      {@Bind.query("p1") int p1, @Bind.header("X-P2") int p2}) async {
    return new Response.ok("");
  }

  @Bind.get()
  Future<Response> getOne(@Bind.path("id") int id) async {
    return new Response.ok("");
  }

  /// MNOP
  /// QRST

  @Bind.get()
  Future<Response> getTwo(@Bind.path("id") int id, @Bind.path("notID") int notID) async {
    return new Response.ok("");
  }

  /// EFGH
  /// IJKL
  @Bind.post()
  Future<Response> createOne(
      @Bind.header("X-Date") DateTime date, @Bind.query("foo") String foo) async {
    return new Response.ok("");
  }
}

/* END DON'T CHANGE WHITESPACE BLOCK */
