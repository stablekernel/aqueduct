import 'package:aqueduct/src/http/http.dart';

class HandlerException implements Exception {
  HandlerException(this._response);

  Response get response => _response;

  final Response _response;
}
