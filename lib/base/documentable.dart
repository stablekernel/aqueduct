part of aqueduct;

Map<String, dynamic> _stripNull(Map<String, dynamic> m) {
  var outMap = <String, dynamic>{};
  m.forEach((k, v) {
    if (v != null) {
      outMap[k] = v;
    }
  });
  return outMap;
}

class APIDocumentable {
  APIDocumentable get documentableChild => null;

  APIDocument documentAPI(PackagePathResolver resolver) => documentableChild?.documentAPI(resolver);
  List<APIPath> documentPaths(PackagePathResolver resolver) => documentableChild?.documentPaths(resolver);
  List<APIOperation> documentOperations(PackagePathResolver resolver) => documentableChild?.documentOperations(resolver);
  List<APIResponse> documentResponsesForOperation(APIOperation operation) => documentableChild?.documentResponsesForOperation(operation);
  APIRequestBody documentRequestBodyForOperation(APIOperation operation) => documentableChild?.documentRequestBodyForOperation(operation);
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

  Map<String, dynamic> asMap({String version: "2.0"}) {
    var m = <String, dynamic>{};

    if (version.startsWith("2.")) {
      m["swagger"] = version;
    } else {
      m["openapi"] = version;
    }
    m["info"] = info.asMap();

    if (version.startsWith("2.")) {
      if (hosts.length > 0) {
        m["host"] = hosts.first.host;
      }
    } else {
      m["hosts"] = hosts.map((host) => host.asMap()).toList();
    }

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
  APIContact contact = new APIContact();
  APILicense license = new APILicense();

  Map<String, dynamic> asMap() {
    return _stripNull({
      "title" : title,
      "description" : description,
      "version" : version,
      "termsOfService" : termsOfServiceURL,
      "contact" : contact.asMap(),
      "license" : license.asMap()
    });
  }
}

class APIContact {
  String name = "default";
  String url = "http://localhost";
  String email = "default";

  Map<String, String> asMap() {
    return {
      "name" : name,
      "url" : url,
      "email" : email
    };
  }
}

class APILicense {
  String name = "default";
  String url = "http://localhost";

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

  Uri get uri {
    return new Uri(scheme: scheme, host: host, path: basePath);
  }

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

  Map<String, dynamic> asMap() {
    return {
      name : scopes
    };
  }
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

  bool get isOAuth2 {
    return type == "oauth2";
  }

  Map<String, dynamic> asMap() {
    var m = <String, dynamic>{
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
  List<APIParameter> parameters = [];
  List<APIOperation> operations = [];

  Map<String, dynamic> asMap() {
    Map<String, dynamic> i = {};

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

  Map<String, dynamic> get _requestBodyParameterMap {
    var param = new APIParameter();
    param.schemaObject = requestBody.schema;
    param.description = requestBody.description;
    param.name = "Body";
    param.deprecated = false;
    param.parameterLocation = APIParameterLocation.body;
    param.required = true;
    return param.asMap();
  }

  static String idForMethod(Object classInstance, Symbol methodSymbol) {
    return "${MirrorSystem.getName(reflect(classInstance).type.simpleName)}.${MirrorSystem.getName(methodSymbol)}";
  }

  static Symbol symbolForID(String operationId, Object classInstance) {
    var components = operationId.split(".");
    if (components.length != 2 || components.first != MirrorSystem.getName(reflect(classInstance).type.simpleName)) {
      return null;
    }

    return new Symbol(components.last);
  }

  Map<String, dynamic> asMap() {
    var m = <String, dynamic>{};

    m["summary"] = summary;
    m["description"] = description;
    m["id"] = id;
    m["deprecated"] = deprecated;
    m["tags"] = tags;
    m["consumes"] = consumes.map((ct) => ct.toString()).toList();
    m["produces"] = produces.map((ct) => ct.toString()).toList();
    m["parameters"] = parameters.map((param) => param.asMap()).toList();
    if (requestBody != null) {
      m["parameters"].add(_requestBodyParameterMap);
    }

    m["responses"] = new Map.fromIterable(responses, key: (APIResponse k) => k.key, value: (APIResponse v) => v.asMap());
    m["security"] = security.map((req) => req.asMap()).toList();

    // m["requestBody"] = requestBody?.asMap();

    return _stripNull(m);
  }
}

class APIResponse {
  String key;
  String description = "";
  APISchemaObject schema;
  Map<String, APIHeader> headers = {};

  int get statusCode {
    if (key == null || key == "default") {
      return null;
    }
    return int.parse(key);
  }
  void set statusCode(int code) {
    key = "$code";
  }


  Map<String, dynamic> asMap() {
    var mappedHeaders = {};
    headers.forEach((headerName, headerObject) {
      mappedHeaders[headerName] = headerObject.asMap();
    });

    return _stripNull({
      "description" : description,
      "schema" : schema?.asMap(),
      "headers" : mappedHeaders
    });
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
  query, header, path, formData, cookie, body
}

class APIParameter {
  static String typeStringForVariableMirror(VariableMirror m) {
    return typeStringForTypeMirror(m.type);
  }

  static String typeStringForTypeMirror(TypeMirror m) {
    if (m.isSubtypeOf(reflectType(int))) {
      return APISchemaObject.FormatInt32;
    } else if (m.isSubtypeOf(reflectType(double))) {
      return APISchemaObject.FormatDouble;
    } else if (m.isSubtypeOf(reflectType(DateTime))) {
      return APISchemaObject.FormatDateTime;
    }

    return null;
  }

  static APIParameterLocation _parameterLocationFromHTTPParameter(_HTTPParameter p) {
    if (p is HTTPPath) {
      return APIParameterLocation.path;
    } else if (p is HTTPQuery) {
      return APIParameterLocation.query;
    } else if (p is HTTPHeader) {
      return APIParameterLocation.header;
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
      case APIParameterLocation.body: return "body";
    }
    return null;
  }

  String name;
  String description = "";
  bool required = false;
  bool deprecated = false;
  APISchemaObject schemaObject;
  APIParameterLocation parameterLocation;

  Map<String, dynamic> asMap() {
    var m = <String, dynamic>{};
    m["name"] = name;
    m["description"] = description;
    m["required"] = (parameterLocation == APIParameterLocation.path ? true : required);
    m["deprecated"] = deprecated;
    m["schema"] = schemaObject?.asMap();
    m["in"] = parameterLocationStringForType(parameterLocation);

    return _stripNull(m);
  }
}

class APIRequestBody {
  String description;
  APISchemaObject schema;
  bool required = true;

  Map<String, dynamic> asMap() {
    return {
      "description" : description,
      "schema" : schema.asMap(),
      "required" : required
    };
  }
}

class APISchemaObject {
  static const String TypeString = "string";
  static const String TypeArray = "array";
  static const String TypeObject = "object";
  static const String TypeNumber = "number";
  static const String TypeInteger = "integer";
  static const String TypeBoolean = "boolean";

  static const String FormatInt32 = "int32";
  static const String FormatInt64 = "int64";
  static const String FormatDouble = "double";
  static const String FormatBase64 = "byte";
  static const String FormatBinary = "binary";
  static const String FormatDate = "date";
  static const String FormatDateTime = "date-time";
  static const String FormatPassword = "password";
  static const String FormatEmail = "email";

  String title;
  String type;
  String format;
  String description;
  String example;
  bool required = true;
  bool readOnly = false;
  bool deprecated = false;
  APISchemaObject items;
  Map<String, APISchemaObject> properties;
  Map<String, APISchemaObject> additionalProperties;

  APISchemaObject({this.properties, this.additionalProperties}) : type = APISchemaObject.TypeObject;
  APISchemaObject.string() : type = APISchemaObject.TypeString;
  APISchemaObject.int() : type = APISchemaObject.TypeInteger, format = APISchemaObject.FormatInt32;
  APISchemaObject.fromTypeMirror(TypeMirror m) {
    type = typeFromTypeMirror(m);
    format = formatFromTypeMirror(m);
  }

  static String typeFromTypeMirror(TypeMirror m) {
    if (m.isSubtypeOf(reflectType(String))) {
      return TypeString;
    } else if (m.isSubtypeOf(reflectType(List))) {
      return TypeArray;
    } else if (m.isSubtypeOf(reflectType(Map))) {
      return TypeObject;
    } else if (m.isSubtypeOf(reflectType(int))) {
      return TypeInteger;
    } else if (m.isSubtypeOf(reflectType(num))) {
      return TypeNumber;
    } else if (m.isSubtypeOf(reflectType(bool))) {
      return TypeBoolean;
    } else if (m.isSubtypeOf(reflectType(DateTime))) {
      return TypeString;
    }

    return null;
  }

  static String formatFromTypeMirror(TypeMirror m) {
    if (m.isSubtypeOf(reflectType(int))) {
      return FormatInt32;
    } else if (m.isSubtypeOf(reflectType(double))) {
      return FormatDouble;
    }  else if (m.isSubtypeOf(reflectType(DateTime))) {
      return FormatDateTime;
    }

    return null;
  }

  Map<String, dynamic> asMap() {
    var m = <String, dynamic>{};

    m["type"] = type;
    m["required"] = required;
    m["readOnly"] = readOnly;
    m["deprecated"] = deprecated;

    if (title != null) {
      m["title"] = title;
    }
    if (format != null) {
      m["format"] = format;
    }

    if (description != null) {
      m["description"] = description;
    }

    if (example != null) {
      m["example"] = example;
    }

    if (items != null) {
      m["items"] = items.asMap();
    }
    if (properties != null) {
      m["properties"] = new Map.fromIterable(properties.keys, key: (key) => key, value: (key) => properties[key].asMap());
    }
    if (additionalProperties != null) {
      m["additionalProperties"] = new Map.fromIterable(additionalProperties.keys, key: (key) => key, value: (key) => additionalProperties[key].asMap());
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

      var remainingPath = uri.pathSegments.sublist(1).join("/");
      return "$packagePath$remainingPath";
    }
    return uri.path;
  }
}