part of monadart;

class RoutedHttpRequest {
  final HttpRequest request;
  final Map<String, String> pathValues;

  RoutedHttpRequest(this.request, this.pathValues);
}