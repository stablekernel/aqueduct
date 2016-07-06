part of aqueduct;

abstract class APIDocumentable {
  dynamic document(PackagePathResolver resolver);
}

class APIDocument {
  APIInfo info = new APIInfo();
  List<APIHost> hosts = [];
  List<ContentType> consumes = [];
  List<ContentType> produces = [];
  List<APISecurityRequirement> securityRequirements = [];
  List<APIPath> paths = [];

  Map<String, dynamic> asMap() {
    var m = {};

    m["openapi"] = "3.0.*";
    m["info"] = info.asMap();
    m["hosts"] = hosts;
    m["consumes"] = consumes.map((ct) => ct.toString()).toList();
    m["produces"] = produces.map((ct) => ct.toString()).toList();
    m["security"] = securityRequirements.map((sec) => sec.asMap()).toList();
    m["paths"] = {};

    paths.forEach((apiPath) {
      m["paths"][apiPath.path] = apiPath.asMap();
    });

    return m;
  }
}

class APIInfo {
  String title = "API";
  String description = "Description";
  String version = "1.0";
  String termsOfServiceURL = "";
  APIContact contact;
  APILicense license;

  Map<String, String> asMap() {
    return {
      "title" : title,
      "description" : description,
      "version" : version,
      "termsOfService" : termsOfServiceURL,
      "contact" : contact?.asMap(),
      "license" : license?.asMap()
    };
  }
}

class APIContact {
  String name;
  String URL;
  String email;

  Map<String, String> asMap() {
    return {
      "name" : name,
      "url" : URL,
      "email" : email
    };
  }
}

class APILicense {
  String name;
  String URL;

  Map<String, String> asMap() {
    return {
      "name" : name,
      "url" : URL
    };
  }
}

class APIHost {
  String host = "localhost:8000";
  String basePath = "/";
  String scheme = "http";

  Map<String, String> asMap() {
    return {
      "host" : host,
      "basePath" : basePath,
      "scheme" : scheme
    };
  }
}


class APISecurityRequirement {
  String name;
  String type;

  Map<String, dynamic> asMap() {
    return {};
  }
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

class APIPath {
  String path;

  String summary = "";
  String description = "";
  List<APIOperation> operations = [];
  List<APIParameter> parameters = [];

  Map<String, dynamic> asMap() {
    Map<String, dynamic> i = {};
    i["description"] = description;
    i["summary"] = summary;
    i["parameters"] = parameters.map((p) => p.asMap()).toList();

    operations.forEach((op) {
      i[op.method] = op.asMap();
    });

    return i;
  }
}

class APIOperation {
  String method;

  String summary = "";
  String description = "";
  String id;
  bool deprecated = false;

  List<String> tags = [];
  List<ContentType> consumes = [];
  List<ContentType> produces = [];
  List<APIParameter> parameters = [];
  List<APISecurityRequirement> security = [];
  APIRequestBody requestBody;
  List<APIResponse> responses = [];

  Map<String, dynamic> asMap() {
    var m = {};

    m["summary"] = summary;
    m["description"] = description;
    m["id"] = id;
    m["deprecated"] = deprecated;
    m["tags"] = tags;
    m["consumes"] = consumes.map((ct) => ct.toString()).toList();
    m["produces"] = produces.map((ct) => ct.toString()).toList();
    m["parameters"] = parameters.map((param) => param.asMap()).toList();
    m["requestBody"] = requestBody?.asMap();
    m["responses"] = {};
    responses.forEach((resp) {
      m["responses"][resp.key] = resp.asMap();
    });

    return m;
  }
}

class APIResponse {
  String key;
  String description;
  APISchemaObject schema;
  Map<String, APIHeader> headers = {};
  set statusCode(int code) {
    key = "$code";
  }

  Map<String, dynamic> asMap() {
    var mappedHeaders = {};
    headers.forEach((headerName, headerObject) {
      mappedHeaders[headerName] = headerObject.asMap();
    });

    return {
      "description" : description,
      "schema" : schema.asMap(),
      "headers" : mappedHeaders
    };
  }
}

enum APIHeaderType {
  string, number, integer, boolean
}

class APIHeader {
  String description;
  APIHeaderType type;

  static String headerTypeStringForType(APIHeaderType type) {
    switch (type) {
      case APIHeaderType.string: return "string";
      case APIHeaderType.number: return "number";
      case APIHeaderType.integer: return "integer";
      case APIHeaderType.boolean: return "boolean";
    }
    return null;
  }

  Map<String, dynamic> asMap() {
    return {
      "description" : description,
      "type" : headerTypeStringForType(type)
    };
  }
}

enum APIParameterLocation {
  query, header, path, formData, cookie
}

class APIParameter {
  static String typeStringForVariableMirror(VariableMirror m) {
    if (m.type.isSubtypeOf(reflectType(int))) {
      return "int32";
    } else if (m.type.isSubtypeOf(reflectType(double))) {
      return "double";
    } else if (m.type.isSubtypeOf(reflectType(String))) {
      return "string";
    } else if (m.type.isSubtypeOf(reflectType(bool))) {
      return "boolean";
    } else if (m.type.isSubtypeOf(reflectType(DateTime))) {
      return "date-time";
    }

    return null;
  }

  String name;
  String description;
  String type;
  bool required = false;
  bool deprecated = false;
  APISchemaObject schemaObject;
  APIParameterLocation parameterLocation;

  Map<String, dynamic> asMap() {
    var m = {};
    m["name"] = name;
    m["description"] = description;
    m["required"] = (parameterLocation == APIParameterLocation.path ? true : required);
    m["deprecated"] = deprecated;
    m["schema"] = schemaObject?.asMap();
    m["type"] = type;

    switch (parameterLocation) {
      case APIParameterLocation.query: m["in"] = "query"; break;
      case APIParameterLocation.header: m["in"] = "header"; break;
      case APIParameterLocation.path: m["in"] = "path"; break;
      case APIParameterLocation.formData: m["in"] = "formData"; break;
      case APIParameterLocation.cookie: m["in"] = "cookie"; break;
    }

    return m;
  }
}

class APIRequestBody {
  String description;
  APISchemaObject schema;
  bool required;

  Map<String, dynamic> asMap() {
    return {
      "description" : description,
      "schema" : schema.asMap(),
      "required" : required
    };
  }
}

const String APISchemaObjectTypeString = "string";
const String APISchemaObjectTypeArray = "array";
const String APISchemaObjectTypeObject = "object";
const String APISchemaObjectTypeNumber = "number";

const String APISchemaObjectFormatInt32 = "int32";
const String APISchemaObjectFormatInt64 = "int64";
const String APISchemaObjectFormatDouble = "double";
const String APISchemaObjectFormatString = "string";
const String APISchemaObjectFormatBase64 = "byte";
const String APISchemaObjectFormatBinary = "binary";
const String APISchemaObjectFormatBoolean = "boolean";
const String APISchemaObjectFormatDateTime = "date-time";
const String APISchemaObjectFormatPassword = "password";
const String APISchemaObjectFormatEmail = "email";

class APISchemaObject {
  String title;
  String type;
  String format;
  String description;
  bool required;
  bool readOnly = false;
  String example;
  bool deprecated = false;
  Map<String, APISchemaObject> properties = {};
  Map<String, APISchemaObject> additionalProperties = {};

  Map<String, dynamic> asMap() {
    var m = {};
    m["title"] = title;
    m["type"] = type;
    m["format"] = format;
    m["description"] = description;
    m["required"] = required;
    m["readOnly"] = readOnly;
    m["example"] = example;
    m["deprecated"] = deprecated;

    m["properties"] = properties;
    m["additionalProperties"] = additionalProperties;

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

      var remainingPath = uri.pathSegments.sublist(1).join("/");
      return "$packagePath$remainingPath";
    }
    return uri.path;
  }
}