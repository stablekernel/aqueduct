part of monadart;

class ResourceRequest {

  final HttpRequest request;
  HttpResponse get response => request.response;

  Map<String, String> pathParameters = null;
  Map<dynamic, dynamic> context = null;

  ResourceRequest(HttpRequest req) : request = req {

  }

}