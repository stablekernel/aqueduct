import 'package:aqueduct/src/http/http.dart';

abstract class HandlerException implements Exception {
  RequestOrResponse get requestOrResponse;
}