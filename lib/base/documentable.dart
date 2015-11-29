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
  Map<String, APIParameter> pathParameters;
  Map<String, APIParameter> queryParameters;
  List<String> responseFormats;
  List<Map<String, String>> possibleErrors;

  String sampleSuccessfulResponse;
}

class APIParameter {
  String description;
  String type;
  bool required;
}