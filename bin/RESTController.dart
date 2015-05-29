import 'dart:mirrors';
import 'dart:io';

class RESTController {
  call(HttpRequest req) {
    Symbol method = new Symbol("${req.method.toLowerCase()}");

    InstanceMirror m = reflect(this);
    try {
      reflect(this).invoke(method, [req]);
    } catch (e, stacktrace) {
      print("${req.uri} ${e}, ${stacktrace}");

      req.response.statusCode = 500;
    } finally {
      req.response.close();
    }
  }

  noSuchMethod(Invocation invocation) {
    var request = invocation.positionalArguments[0] as HttpRequest;
    request.response.statusCode = 501;
  }
}