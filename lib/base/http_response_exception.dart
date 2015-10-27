part of monadart;

class HttpResponseException implements Exception {
  String message;
  int statusCode;

  HttpResponseException(this.statusCode, this.message);

  Response response() {
    return new Response(statusCode, {}, {
      "error" : message
    });
  }
}