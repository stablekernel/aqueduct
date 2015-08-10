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
    expect(p.matchesInUri(new Uri.http("test.com", "/")), {});
  });

  test("Literal", () {
    ResourcePattern p = new ResourcePattern("/player");
    expect(p.matchesInUri(new Uri.http("test.com", "/player")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/notplayer")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/playernot")), null);
  });

  test("Literal Many", () {
    ResourcePattern p = new ResourcePattern("/player/one");
    expect(p.matchesInUri(new Uri.http("test.com", "/player/one")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/player/two")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/notplayer/one")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/notplayer/two")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Star", () {
    ResourcePattern p = new ResourcePattern("/*");
    expect(p.matchesInUri(new Uri.http("test.com", "/player/2mnasd")), containsPair(ResourcePattern.remainingPath, "player/2mnasd"));
    expect(p.matchesInUri(new Uri.http("test.com", "/player/one/foobar/hello")), containsPair(ResourcePattern.remainingPath, "player/one/foobar/hello"));
    expect(p.matchesInUri(new Uri.http("test.com", "/")), containsPair(ResourcePattern.remainingPath, ""));
  });

  test("Literal Star", () {
    ResourcePattern p = new ResourcePattern("/player/*");
    expect(p.matchesInUri(new Uri.http("test.com", "/player/2mnasd")), containsPair(ResourcePattern.remainingPath, "2mnasd"));
    expect(p.matchesInUri(new Uri.http("test.com", "/player/one/foobar/hello")), containsPair(ResourcePattern.remainingPath, "one/foobar/hello"));
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Variable Plain", () {
    ResourcePattern p = new ResourcePattern("/:id");
    expect(p.matchesInUri(new Uri.http("test.com", "/player")), containsPair("id", "player"));
    expect(p.matchesInUri(new Uri.http("test.com", "/player/foobar")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Literal Variable", () {
    ResourcePattern p = new ResourcePattern("/player/:id");
    expect(p.matchesInUri(new Uri.http("test.com", "/player")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/player/foobar")), containsPair("id", "foobar"));
    expect(p.matchesInUri(new Uri.http("test.com", "/player/foobar/etc")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Basic", () {
    ResourcePattern p = new ResourcePattern("/a/[b]");
    expect(p.matchesInUri(new Uri.http("test.com", "/a")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Multiple", () {
    ResourcePattern p = new ResourcePattern("/a/[b/c]");
    expect(p.matchesInUri(new Uri.http("test.com", "/a")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional Imbricated", () {
    ResourcePattern p = new ResourcePattern("/a/[b/[c]]");
    expect(p.matchesInUri(new Uri.http("test.com", "/a")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/X/c")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/a/a")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c/d")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Optional w/ variable", () {
    ResourcePattern p = new ResourcePattern("/a/[:b]");
    expect(p.matchesInUri(new Uri.http("test.com", "/a")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/player")), containsPair("b", "player"));
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/")), null);
  });

  test("Optiona imbricated w/ variables", () {
    ResourcePattern p = new ResourcePattern("/a/[:b/[:c]]");
    expect(p.matchesInUri(new Uri.http("test.com", "/a")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b")), {"b" : "b"});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c")), {"b" : "b", "c" : "c"});
    expect(p.matchesInUri(new Uri.http("test.com", "/a/b/c/d")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/b/b/c/d")), null);
  });

  test("Sub Pattern", () {
    ResourcePattern p = new ResourcePattern(r"/:b(\D+)");
    expect(p.matchesInUri(new Uri.http("test.com", "/raw")), containsPair("b", "raw"));
    expect(p.matchesInUri(new Uri.http("test.com", "/1")), null);
  });

  test("Sub Pattern", () {
    ResourcePattern p = new ResourcePattern(r"/:b(7\w*)");
    expect(p.matchesInUri(new Uri.http("test.com", "/raw")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/1")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/7")), containsPair("b", "7"));
    expect(p.matchesInUri(new Uri.http("test.com", "/7abc")), containsPair("b", "7abc"));
  });

  test("All", () {
    ResourcePattern p = new ResourcePattern(r"/literal/[:b(\d+)/*]");
    expect(p.matchesInUri(new Uri.http("test.com", "/literal")), {});
    expect(p.matchesInUri(new Uri.http("test.com", "/literal/23")), allOf([containsPair("b", "23"), containsPair(ResourcePattern.remainingPath, "")]));
    expect(p.matchesInUri(new Uri.http("test.com", "/nonliteral/23/abc")), null);
    expect(p.matchesInUri(new Uri.http("test.com", "/literal/123/foobar/x")), allOf([containsPair("b", "123"), containsPair(ResourcePattern.remainingPath, "foobar/x")]));
  });


}