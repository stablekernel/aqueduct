part of monadart;

class Response {
  String body;
  Map<String, String> headers;
  int statusCode;

  Response(int statusCode, Map<String, String> headers, String body) {
    this.body = body;
    this.headers = headers;
    this.statusCode = statusCode;
  }

  Response.ok(String body, {Map<String, String> headers}) : this(200, headers, body);
  Response.created(String location, {String body, Map<String, String> headers}) {
    this.headers = headers;
    this.body = body;
    this.statusCode = 201;

    this.headers[HttpHeaders.LOCATION] = location;
  }
  Response.accepted({Map<String, String> headers}) : this(202, headers, null);

  Response.badRequest({Map<String, String> headers, String body}) : this(400, headers, body);
  Response.unauthorized({Map<String, String> headers, String body}) : this(401, headers, body);
  Response.forbidden({Map<String, String> headers, String body}) : this(403, headers, body);
  Response.notFound({Map<String, String> headers, String body}) : this(404, headers, body);
  Response.conflict({Map<String, String> headers, String body}) : this(409, headers, body);
  Response.gone({Map<String, String> headers, String body}) : this(410, headers, body);

  Response.serverError({Map<String, String> headers, String body}) : this(500, headers, body);

}