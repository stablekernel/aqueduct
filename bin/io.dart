import 'dart:async';

Future main() async {
  var output = await outer("y");
  print("$output");
}

Future<String> outer(String s) async {
  try {
    var res = await a(s);
    return res;
  } catch (any) {
    return "caught try-catch";
  }
}

Future<String> a(String s) => b(s);

Future<String> b(String s) async => await c(s);

Future<String> c(String s) async => throw new Exception("hello");
