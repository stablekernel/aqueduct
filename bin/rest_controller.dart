part of monadart;

class RESTController {

  static String pattern() {
    return null;
  }

  call(request) {
    if(request is RoutedHttpRequest) {
      var req = (request as RoutedHttpRequest).request;
      var params = (request as RoutedHttpRequest).pathValues;

      Symbol method = new Symbol("${req.method.toLowerCase()}");

      var symbolicatedParams = new Map<Symbol, dynamic>();
      params.forEach((key, value) {
        symbolicatedParams[new Symbol(key)] = value;
      });

      try {
        reflect(this).invoke(method, [req], symbolicatedParams);
      } catch (e, stacktrace) {
        print("${req.uri} ${e}, ${stacktrace}");

        req.response.statusCode = 500;
      } finally {
        req.response.close();
      }
    } else if(request is HttpRequest) {
      var req = request as HttpRequest;
      Symbol method = new Symbol("${req.method.toLowerCase()}");

      try {
        reflect(this).invoke(method, [req]);
      } catch (e, stacktrace) {
        print("${req.uri} ${e}, ${stacktrace}");

        req.response.statusCode = 500;
      } finally {
        req.response.close();
      }
    }
  }

  noSuchMethod(Invocation invocation) {
    var request = invocation.positionalArguments[0] as HttpRequest;
    request.response.statusCode = 501;
  }
}