part of aqueduct;

class APIDocumentable {
  APIDocumentable get documentableChild => null;

  APIDocument documentAPI(PackagePathResolver resolver) => documentableChild?.documentAPI(resolver);
  List<APIPath> documentPaths(PackagePathResolver resolver) => documentableChild?.documentPaths(resolver);
  List<APIOperation> documentOperations(PackagePathResolver resolver) => documentableChild?.documentOperations(resolver);
  List<APIResponse> documentResponsesForOperation(APIOperation operation) => documentableChild?.documentResponsesForOperation(operation);
  Map<String, APISecurityScheme> documentSecuritySchemes(PackagePathResolver resolver) => documentableChild?.documentSecuritySchemes(resolver);
}

class APIDocument {
  APIInfo info = new APIInfo();
  List<APIHost> hosts = [];
  List<ContentType> consumes = [];
  List<ContentType> produces = [];
  List<APIPath> paths = [];
  List<APISecurityRequirement> securityRequirements = [];
  Map<String, APISecurityScheme> securitySchemes = {};

  Map<String, dynamic> asMap() {
    var m = {};

    m["openapi"] = "3.0.*";
    m["info"] = info.asMap();
    m["hosts"] = hosts.map((host) => host.asMap()).toList();
    m["consumes"] = consumes.map((ct) => ct.toString()).toList();
    m["produces"] = produces.map((ct) => ct.toString()).toList();
    m["security"] = securityRequirements.map((sec) => sec.name).toList();
    m["paths"] = new Map.fromIterable(paths, key: (APIPath k) => k.path, value: (APIPath v) => v.asMap());

    var mappedSchemes = {};
    securitySchemes?.forEach((k, scheme) {
      mappedSchemes[k] = scheme.asMap();
    });
    m["securityDefinitions"] = mappedSchemes;

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
  String url;
  String email;

  Map<String, String> asMap() {
    return {
      "name" : name,
      "url" : url,
      "email" : email
    };
  }
}

class APILicense {
  String name;
  String url;

  Map<String, String> asMap() {
    return {
      "name" : name,
      "url" : url
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
  List<APISecurityScope> scopes;
}

class APISecurityScope {
  String name;
  String description;

  Map<String, String> asMap() {
    return {
      name : description
    };
  }
}

class APISecurityDefinition {
  String name;
  APISecurityScheme scheme;

  Map<String, dynamic> asMap() => scheme.asMap();
}


enum APISecuritySchemeFlow {
  implicit, password, application, accessCode
}

class APISecurityScheme {
  static String stringForFlow(APISecuritySchemeFlow flow) {
    switch (flow) {
      case APISecuritySchemeFlow.accessCode: return "accessCode";
      case APISecuritySchemeFlow.password: return "password";
      case APISecuritySchemeFlow.implicit: return "implicit";
      case APISecuritySchemeFlow.application: return "application";
    }
    return null;
  }
  APISecurityScheme.basic() {
    type = "basic";
  }

  APISecurityScheme.apiKey() {
    type = "apiKey";
  }

  APISecurityScheme.oauth2() {
    type = "oauth2";
  }

  String type;
  String description;

  // API Key
  String apiKeyName;
  APIParameterLocation apiKeyLocation;

  // Oauth2
  APISecuritySchemeFlow oauthFlow;
  String authorizationURL;
  String tokenURL;
  List<APISecurityScope> scopes = [];

  Map<String, dynamic> asMap() {
    var m = {
      "type" : type,
      "description" : description
    };

    if (type == "basic") {
      /* nothing to do */
    } else if (type == "apiKey") {
      m["name"] = apiKeyName;
      m["in"] = APIParameter.parameterLocationStringForType(apiKeyLocation);
    } else if (type == "oauth2") {
      m["flow"] = stringForFlow(oauthFlow);

      if (oauthFlow == APISecuritySchemeFlow.implicit || oauthFlow == APISecuritySchemeFlow.accessCode) {
        m["authorizationUrl"] = authorizationURL;
      }

      if (oauthFlow != APISecuritySchemeFlow.implicit) {
        m["tokenUrl"] = tokenURL;
      }

      m["scopes"] = new Map.fromIterable(scopes, key: (APISecurityScope k) => k.name, value: (APISecurityScope v) => v.description);
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

  static String idForMethod(Object classInstance, Symbol methodSymbol) {
    return "${MirrorSystem.getName(reflect(classInstance).type.simpleName)}.${MirrorSystem.getName(methodSymbol)}";
  }

  static Symbol symbolForId(String operationId, Object classInstance) {
    var components = operationId.split(".");
    if (components.length != 2 || components.first != MirrorSystem.getName(reflect(classInstance).type.simpleName)) {
      return null;
    }

    return new Symbol(components.last);
  }

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
    m["responses"] = new Map.fromIterable(responses, key: (APIResponse k) => k.key, value: (APIResponse v) => v.asMap());
    m["security"] = new Map.fromIterable(security, key: (APISecurityRequirement k) => k.name, value: (APISecurityRequirement v) => v.scopes.map((scope) => scope.name).toList());

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
      return APISchemaObjectFormatInt32;
    } else if (m.type.isSubtypeOf(reflectType(double))) {
      return APISchemaObjectFormatDouble;
    } else if (m.type.isSubtypeOf(reflectType(DateTime))) {
      return APISchemaObjectFormatDateTime;
    }

    return null;
  }

  static String parameterLocationStringForType(APIParameterLocation parameterLocation) {
    switch (parameterLocation) {
      case APIParameterLocation.query: return "query";
      case APIParameterLocation.header: return "header";
      case APIParameterLocation.path: return "path";
      case APIParameterLocation.formData: return "formData";
      case APIParameterLocation.cookie: return "cookie";
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
    m["in"] = parameterLocationStringForType(parameterLocation);

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
const String APISchemaObjectTypeInteger = "integer";
const String APISchemaObjectTypeBoolean = "boolean";

const String APISchemaObjectFormatInt32 = "int32";
const String APISchemaObjectFormatInt64 = "int64";
const String APISchemaObjectFormatDouble = "double";
const String APISchemaObjectFormatBase64 = "byte";
const String APISchemaObjectFormatBinary = "binary";
const String APISchemaObjectFormatDate = "date";
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
  APISchemaObject items;
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

    m["items"] = items?.asMap() ?? {};
    m["properties"] = new Map.fromIterable(properties.keys, key: (key) => key, value: (key) => properties[key].asMap());
    m["additionalProperties"] = new Map.fromIterable(additionalProperties.keys, key: (key) => key, value: (key) => additionalProperties[key].asMap());

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