@TestOn("vm")
import "package:test/test.dart";
import "dart:core";
import '../lib/monadart.dart';

void main() {

  /*
    /literal
    /:name
    /:name(expr)
    /literal/[:optional]
    / *
   */

  test("Root", () {
    ResourcePattern p = new ResourcePattern("");
    var m = p.matchUri(new Uri.http("test.com", "/"));
    expect(m, isNotNull);
    expect(m.segments.length, 0);
  });

  test("Literal", () {
    ResourcePattern p = new ResourcePattern("/player");

    var m = p.matchUri(new Uri.http("test.com", "/player"));
    expect(m, isNotNull);
    expect(m.segments[0], "player");

    expect(p.matchUri(new Uri.http("test.com", "/notplayer")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
    expect(p.matchUri(new Uri.http("test.com", "/playernot")), null);
  });

  test("Literal Many", () {
    ResourcePattern p = new ResourcePattern("/player/one");

    var m = p.matchUri(new Uri.http("test.com", "/player/one"));
    expect(m, isNotNull);
    expect(m.segments[0], "player");
    expect(m.segments[1], "one");
    expect(m.variables.length, 0);

    expect(p.matchUri(new Uri.http("test.com", "/player/two")), null);
    expect(p.matchUri(new Uri.http("test.com", "/notplayer/one")), null);
    expect(p.matchUri(new Uri.http("test.com", "/notplayer/two")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Star", () {
    ResourcePattern p = new ResourcePattern("/*");

    var m = p.matchUri(new Uri.http("test.com", "/player/2mnasd"));
    expect(m.remainingPath, "player/2mnasd");
    expect(m.segments.length, 0);
    expect(m.variables.length, 0);

    m = p.matchUri(new Uri.http("test.com", "/player/one/foobar/hello"));
    expect(m.remainingPath, "player/one/foobar/hello");
    expect(m.segments.length, 0);
    expect(m.variables.length, 0);

    m = p.matchUri(new Uri.http("test.com", "/"));
    expect(m.remainingPath, "");
  });

  test("Literal Star", () {
    ResourcePattern p = new ResourcePattern("/player/*");

    var m = p.matchUri(new Uri.http("test.com", "/player/2mnasd"));
    expect(m.remainingPath, "2mnasd");
    expect(m.segments[0], "player");

    m = p.matchUri(new Uri.http("test.com", "/player/one/foobar/hello"));
    expect(m.remainingPath, "one/foobar/hello");
    expect(m.segments[0], "player");

    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Variable Plain", () {
    ResourcePattern p = new ResourcePattern("/:id");

    var m = p.matchUri(new Uri.http("test.com", "/player"));
    expect(m.variables, containsPair("id", "player"));
    expect(m.segments[0], "player");

    expect(p.matchUri(new Uri.http("test.com", "/player/foobar")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Literal Variable", () {
    ResourcePattern p = new ResourcePattern("/player/:id");

    var m = p.matchUri(new Uri.http("test.com", "/player/foobar"));
    expect(m.variables, containsPair("id", "foobar"));
    expect(m.segments[0], "player");
    expect(m.segments[1], "foobar");

    expect(p.matchUri(new Uri.http("test.com", "/player")), null);
    expect(p.matchUri(new Uri.http("test.com", "/player/foobar/etc")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Basic", () {
    ResourcePattern p = new ResourcePattern("/a/[b]");

    var m = p.matchUri(new Uri.http("test.com", "/a"));
    expect(m.segments[0], "a");

    m = p.matchUri(new Uri.http("test.com", "/a/b"));
    expect(m.segments[0], "a");
    expect(m.segments[1], "b");

    expect(p.matchUri(new Uri.http("test.com", "/a/b/c")), null);
    expect(p.matchUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Multiple", () {
    ResourcePattern p = new ResourcePattern("/a/[b/c]");

    var m = p.matchUri(new Uri.http("test.com", "/a"));
    expect(m.segments[0], "a");

    m = p.matchUri(new Uri.http("test.com", "/a/b/c"));
    expect(m.segments.join(""), "abc");

    expect(p.matchUri(new Uri.http("test.com", "/a/b")), null);
    expect(p.matchUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Imbricated", () {
    ResourcePattern p = new ResourcePattern("/a/[b/[c]]");

    var m = p.matchUri(new Uri.http("test.com", "/a"));
    expect(m.segments[0], "a");

    m = p.matchUri(new Uri.http("test.com", "/a/b"));
    expect(m.segments.join(""), "ab");

    m = p.matchUri(new Uri.http("test.com", "/a/b/c"));
    expect(m.segments.join(""), "abc");

    expect(p.matchUri(new Uri.http("test.com", "/a/X/c")), null);
    expect(p.matchUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchUri(new Uri.http("test.com", "/a/b/c/d")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional w/ variable", () {
    ResourcePattern p = new ResourcePattern("/a/[:b]");

    var m = p.matchUri(new Uri.http("test.com", "/a"));
    expect(m.segments[0], "a");

    m = p.matchUri(new Uri.http("test.com", "/a/player"));
    expect(m.segments.join(""), "aplayer");
    expect(m.variables, containsPair("b", "player"));

    expect(p.matchUri(new Uri.http("test.com", "/a/b/c")), null);
    expect(p.matchUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional imbricated w/ variables", () {
    ResourcePattern p = new ResourcePattern("/a/[:b/[:c]]");

    var m = p.matchUri(new Uri.http("test.com", "/a"));
    expect(m.segments[0], "a");

    m = p.matchUri(new Uri.http("test.com", "/a/b"));
    expect(m.segments.join(""), "ab");
    expect(m.variables, containsPair("b", "b"));

    m = p.matchUri(new Uri.http("test.com", "/a/b/c"));
    expect(m.segments.join(""), "abc");
    expect(m.variables, containsPair("b", "b"));
    expect(m.variables, containsPair("c", "c"));

    expect(p.matchUri(new Uri.http("test.com", "/a/b/c/d")), null);
    expect(p.matchUri(new Uri.http("test.com", "/b/b/c/d")), null);
  });

  test("Sub Pattern", () {
    ResourcePattern p = new ResourcePattern(r"/:b(\D+)");

    var m = p.matchUri(new Uri.http("test.com", "/raw"));
    expect(m.variables, containsPair("b", "raw"));
    expect(m.segments[0], "raw");

    expect(p.matchUri(new Uri.http("test.com", "/1")), null);
  });

  test("Sub Pattern", () {
    ResourcePattern p = new ResourcePattern(r"/:b(7\w*)");

    var m = p.matchUri(new Uri.http("test.com", "/7"));
    expect(m.variables, containsPair("b", "7"));

    m = p.matchUri(new Uri.http("test.com", "/7abc"));
    expect(m.variables, containsPair("b", "7abc"));

    expect(p.matchUri(new Uri.http("test.com", "/raw")), null);
    expect(p.matchUri(new Uri.http("test.com", "/1")), null);

  });

  test("All", () {
    ResourcePattern p = new ResourcePattern(r"/literal/[:b(\d+)/*]");

    var m = p.matchUri(new Uri.http("test.com", "/literal"));
    expect(m.segments[0], "literal");

    m = p.matchUri(new Uri.http("test.com", "/literal/23"));
    expect(m.variables, containsPair("b", "23"));
    expect(m.remainingPath, "");

    m = p.matchUri(new Uri.http("test.com", "/literal/123/foobar/x"));
    expect(m.variables, containsPair("b", "123"));
    expect(m.remainingPath, "foobar/x");

    expect(p.matchUri(new Uri.http("test.com", "/nonliteral/23/abc")), null);
  });

}