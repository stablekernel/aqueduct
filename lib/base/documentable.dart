part of monadart;

class APIDocument {
  List<APIDocumentItem> items = [];

  static APIDocument documentRootHandler(APIDocumentable handler) {
    var d = new APIDocument();
    d.items = handler.document();
    return d;
  }
}

abstract class APIDocumentable {
  List<APIDocumentItem> document();
}

class APIDocumentItem {
  String path;
  String method;
  String authenticationRequirements;
  List<String> acceptedContentTypes;
  List<APIParameter> pathParameters;
  List<APIParameter> queryParameters;
  List<String> responseFormats;
  List<Map<String, String>> possibleErrors;

  String sampleSuccessfulResponse;
}

class APIParameter {
  String key;
  String description;
  String type;
  bool required;
}