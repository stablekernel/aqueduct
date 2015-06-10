part of monadart;

class RESTController {
  call(request) {
    var req = (request as Request).request;
    var pathParams = (request as Request).values["route"];

    Symbol method = new Symbol("${req.method.toLowerCase()}");

    var symbolicatedParams = new Map<Symbol, dynamic>();
    pathParams.forEach((key, value) {
      symbolicatedParams[new Symbol(key)] = value;
    });

    try {
      var response = reflect(this).invoke(method, [request], symbolicatedParams).reflectee;

      respondWith(request, response);
    } catch (e, stacktrace) {
      print("${req.uri} ${e}, ${stacktrace}");

      req.response.statusCode = 500;
    } finally {
      req.response.close();
    }
  }

  respondWith(Request req, Response response) {

    req.request.response.statusCode = response.statusCode;

    if(response.headers != null) {
      response.headers.forEach((k, v) {
        req.request.response.headers.add(k, v);
      });
    }

    if(response.body != null) {
      req.request.response.write(response.body);
    }
  }

  noSuchMethod(Invocation invocation) {
    return new Response(501, null, null);
  }
}
