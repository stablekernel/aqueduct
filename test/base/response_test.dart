import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("Modifying return alue from Response.headers does not impact actual headers", () {
    var response = new Response(0, {}, null);
    response.addHeader("a", "b");

    var headers = response.headers;
    headers["b"] = "c";
    expect(response.headers["a"], "b");
    expect(response.headers["b"], isNull);
    expect(response.headers.length, 1);
  });

  test("Headers get lowercased when set in default constructor", () {
    var response = new Response(0, {"AbC" : "b"}, null);
    expect(response.headers["abc"], "b");
    expect(response.headers.length, 1);
  });

  test("Headers get lowercased when set in convenience constructors", () {
    var response = new Response.ok(null, headers: {"ABCe" : "b"});
    expect(response.headers["abce"], "b");
    expect(response.headers.length, 1);

    response = new Response.created("http://redirect.com", headers: {"ABCe" : "b"});
    expect(response.headers["abce"], "b");
    expect(response.headers["location"], "http://redirect.com");
    expect(response.headers.length, 2);
  });

  test("Headers get lowercased when set manually", () {
    var response = new Response(0, {"AbCe" : "b", "XYZ" : "c"}, null);
    response.addHeader("ABCe", "b");
    expect(response.headers["abce"], "b");
    expect(response.headers["xyz"], "c");
    expect(response.headers.length, 2);
  });

  test("Headers get lowercased when set from Map", () {
    var response = new Response(0, {}, null);
    response.headers = {
      "ABCe" : "b",
      "XYZ" : "c"
    };
    expect(response.headers["abce"], "b");
    expect(response.headers["xyz"], "c");
    expect(response.headers.length, 2);
  });
}