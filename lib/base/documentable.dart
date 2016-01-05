part of monadart;

class APIHeader {
  String title = "API";
  String description = "Description";
  String version = "1.0";

  Map<String, String> asMap() {
    return {
      "title" : title,
      "description" : description,
      "version" : version
    };
  }
}

class APIDocument {
  APIHeader header = new APIHeader();
  List<APIDocumentItem> items = [];
  String host = "localhost:8080";
  List<String> schemes = ["http", "https"];

  List<APISecurityItem> securityItems = [
    new APISecurityItem()
      ..name = "client_auth"
      ..description = "Authorization: Basic base64({ClientID}:{ClientSecret})"
      ..type = APISecurityType.basic,
    new APISecurityItem()
      ..name = "token"
      ..description = "Authorization: Bearer {Token}"
      ..type = APISecurityType.oauth2
      ..tokenURL = ""
      ..flow = "password"
  ];

  Map<String, dynamic> asMap() {
    var m = {};

    m["swagger"] = "2.0";
    m["info"] = header.asMap();
    m["host"] = host;
    m["schemes"] = schemes;

    if (securityItems != null) {
      var sec = {};
      securityItems.forEach((si) {
        sec[si.name] = si.asMap();
      });
      m["securityDefinitions"] = sec;
    }

    Map<String, Map<String, APIDocumentItem>> coalesced = {};
    items.forEach((m) {
      var existing = coalesced[m.path];
      if (existing != null) {
        existing[m.method] = m.asMap();
      } else {
        existing = {
          m.method : m.asMap()
        };
        coalesced[m.path] = existing;
      }
    });
    m["paths"] = coalesced;

    return m;
  }
}

abstract class APIDocumentable {
  List<APIDocumentItem> document(PackagePathResolver resolver);
}

enum APISecurityType {
  oauth2, basic
}

class APISecurityItem {
  String name;

  APISecurityType type;
  String flow;
  String tokenURL;
  String description;

  Map<String, dynamic> asMap() {
    var m = {};

    m["description"] = description;

    switch(type) {
      case APISecurityType.basic: {
          m["type"] = "basic";
      } break;
      case APISecurityType.oauth2: {
        m["type"] = "oauth2";
        if (flow != null) {
          m["flow"] = flow;
        }

        if (tokenURL != null) {
          m["tokenUrl"] = tokenURL;
        }
        m["scopes"] = {"default" : "default"};
      } break;
    }
    return m;
  }
}

class APIDocumentItem {
  String path;
  String method;
  String securityItemName;
  String description;
  List<String> acceptedContentTypes;
  List<APIParameter> pathParameters;
  List<APIParameter> queryParameters;
  List<String> responseFormats;

  Map<String, dynamic> asMap() {
    Map<String, dynamic> i = {};
    i["description"] = description ?? "";
    i["produces"] = responseFormats;

    var combined = [];
    combined.addAll(pathParameters);
    combined.addAll(queryParameters);
    i["parameters"] = combined.map((p) => p.asMap()).toList();

    i["consumes"] = acceptedContentTypes;

    if (securityItemName != null) {
      i["security"] = [{securityItemName : []}];
    }

    return i;
  }

  String toString() {
    return "$path $method $securityItemName $acceptedContentTypes $pathParameters $queryParameters $responseFormats";
  }
}

enum APIParameterLocation {
  query, header, path, formData, body
}

class APIParameter {
  String key;
  String description;
  String type;
  bool required;

  APIParameterLocation parameterLocation;

  String toString() {
    return "$type $key $required $description";
  }

  Map<String, dynamic> asMap() {
    var m = {};
    m["name"] = key;

    switch (parameterLocation) {
      case APIParameterLocation.query: m["in"] = "query"; break;
      case APIParameterLocation.header: m["in"] = "header"; break;
      case APIParameterLocation.path: m["in"] = "path"; break;
      case APIParameterLocation.formData: m["in"] = "formData"; break;
      case APIParameterLocation.body: m["in"] = "body"; break;
    }

    m["required"] = required;

    switch(type) {
      case "int" : m["type"] = "integer"; break;
      case "String" : m["type"] = "string"; break;
      case "bool" : m["type"] = "bool"; break;
      case "double" : m["type"] = "number"; break;
      default: m["type"] = "string";
    }

    return m;
  }
}

class PackagePathResolver {
  PackagePathResolver(String packageMapPath) {
    var contents = new File(packageMapPath).readAsStringSync();
    var lines = contents
        .split("\n")
        .where((l) => !l.startsWith("#") && l.indexOf(":") != -1)
        .map((l) {
          var firstColonIdx = l.indexOf(":");
          var packageName = l.substring(0, firstColonIdx);
          var packagePath = l.substring(firstColonIdx + 1, l.length).replaceFirst(r"file://", "");
          return [packageName, packagePath];
        });
    _map = new Map.fromIterable(lines, key: (k) => k.first, value: (v) => v.last);
  }

  Map<String, String> _map;

  String resolve(Uri uri) {
    if (uri.scheme == "package") {
      var firstElement = uri.pathSegments.first;
      var packagePath = _map[firstElement];
      if (packagePath == null) {
        throw new Exception("Package $firstElement could not be resolved.");
      }
      print("$uri");
      var remainingPath = uri.pathSegments.sublist(1).join("/");
      return "$packagePath$remainingPath";
    }
    return uri.path;
  }
}