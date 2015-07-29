part of monadart;

class Request {
  final HttpRequest request;
  Map values;

  Request(HttpRequest req) : request = req {
    values = {};
  }

  void addValue(String key, dynamic value) {
    values[key] = value;
  }
}