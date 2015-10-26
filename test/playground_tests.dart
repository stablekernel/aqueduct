import 'package:test/test.dart';
import '../lib/monadart.dart';
import 'dart:async';
import 'package:http/http.dart' as http;


Future main() async {

  test("Something", () async {
    var u = new U();
    u.method();
  });
}


class T {
  void method() {
    print("T impl");
  }
}

class U extends T {
  @override
  void method() {
    print("U impl");
  }
}