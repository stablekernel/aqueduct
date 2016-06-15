part of aqueduct;

class HttpResponseException implements Exception {
  String message;
  int statusCode;

  HttpResponseException(this.statusCode, this.message);

  Response response() {
    return new Response(statusCode, {HttpHeaders.CONTENT_TYPE: ContentType.JSON}, {"error": message});
  }
}
