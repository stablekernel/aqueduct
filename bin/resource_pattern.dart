part of monadart;

class ResourcePattern {

  static String remainingPath = "remainingPath";

  ResourcePatternSet matchHead;

  ResourcePattern(String patternString) {
    List<String> pathElements = splitPattern(patternString);

    List<ResourcePatternElement> elems = resourceElementsFromPathElements(patternString);

    matchHead = matchSpecFromElements(pathElements, elems);
  }

  static ResourcePatternSet matchSpecFromElements(List<String> pathElements, List<ResourcePatternElement> resourceElements) {
    // These two arrays should be identical in size by the time they get here

    ResourcePatternSet setHead = new ResourcePatternSet();
    ResourcePatternSet setPtr = setHead;

    for(int i = 0; i < pathElements.length; i++) {
      String seg = pathElements[i];

      if(seg.startsWith("[")) {
        ResourcePatternSet set = new ResourcePatternSet();
        setPtr.nextOptionalSet = set;

        setPtr = set;
      }

      setPtr.addElement(resourceElements[i]);

      for(int i = seg.length - 1; i >= 0; i--) {
        if(seg[i] == "]") {
          setPtr = setPtr.parentSet;
        } else {
          break;
        }
      }
    }

    if(setPtr != setHead) {
      throw new ArgumentError("unmatched brackets in optional paths");
    }

    return setHead;
  }

  static List<String> splitPattern(String patternString) {
    return patternString.split("/").fold(new List<String>(), (List<String> accum, String e) {
      var trimmed = e.trim();
      if(trimmed.length > 0) {
        accum.add(trimmed);
      }
      return accum;
    });
  }


  static List<ResourcePatternElement> resourceElementsFromPathElements(String patternString) {
    var expr = new RegExp(r"[\[\]]");
    return splitPattern(patternString).map((segment) => new ResourcePatternElement(segment.replaceAll(expr, ""))).toList();
  }

  Map<String, String> matchesInUri(Uri uri) {
    Map<String, String> namedParams = {};

    var incomingPathSegments = uri.pathSegments;
    var incomingPathIndex = 0;
    var resourceSet = matchHead;
    var resourceIterator = resourceSet.elements.iterator;

    while(resourceSet != null) {
      while (resourceIterator.moveNext()) {
        // If we run into a *, then we're definitely a match so just grab the end of the path and return it.

        var resourceSegment = resourceIterator.current;
        if (resourceSegment.matchesRemaining) {
          var remainingString = incomingPathSegments.sublist(incomingPathIndex, incomingPathSegments.length).join("/");
          namedParams[remainingPath] = remainingString;

          return namedParams;
        } else {
          // If we're out of path segments, then we don't match
          if(incomingPathIndex >= incomingPathSegments.length) {
            return null;
          }

          var pathSegment = incomingPathSegments[incomingPathIndex];
          incomingPathIndex ++;

          bool match = resourceSegment.fullMatchForString(pathSegment);
          if(!match) {
            // There was a path segment available, but it did not match
            return null;
          }

          // We match!
          if(resourceSegment.name != null) {
            namedParams[resourceSegment.name] = pathSegment;
          }
        }
      }
      resourceSet = resourceSet.nextOptionalSet;

      // If we have path remaining, then we either have optional left or we don't have a match
      if(incomingPathIndex < incomingPathSegments.length) {
        if(resourceSet == null) {
          return null;
        } else {
          resourceIterator = resourceSet.elements.iterator;
        }
      }
    }

    return namedParams;
  }
}

class ResourcePatternSet {
  List<ResourcePatternElement> elements = [];

  ResourcePatternSet parentSet;
  ResourcePatternSet _nextOptionalSet;
  ResourcePatternSet get nextOptionalSet => _nextOptionalSet;
  void set nextOptionalSet(ResourcePatternSet s) {
    _nextOptionalSet = s;
    s.parentSet = this;
  }

  void addElement(ResourcePatternElement e) {
    elements.add(e);
  }

  //Map<String, String> matchesIn
}

class ResourcePatternElement {
  bool matchesRemaining = false;
  String name;
  RegExp matchRegex;

  ResourcePatternElement(String segment) {
    if(segment.startsWith(":")) {
      var contents = segment.substring(1, segment.length);
      constructFromString(contents);
    } else if(segment == "*") {
      matchesRemaining = true;
    } else {
      matchRegex = new RegExp(segment);
    }
  }

  // I'd prefer that this used a outer non-capturing group on the parantheses after the name;
  // but apparently this regex parser won't pick up the capture group inside the noncapturing group for some reason
  static RegExp patternFinder = new RegExp(r"^(\w+)(\(([^\)]+)\))?$", caseSensitive: false);

  void constructFromString(String str) {
    Match m = patternFinder.firstMatch(str);
    if(m == null) {
      throw new ArgumentError("invalid resource pattern segment ${str}, available formats are the following: literal, *, {name}, {name(pattern)}");
    }

    name = m.group(1);

    var matchString = ".+";
    if(m.groupCount == 3) {
      if(m.group(2) != null) {
        matchString = m.group(2);
      }
    }

    matchRegex = new RegExp(r"^" + "${matchString}" + r"$", caseSensitive:false);
  }

  bool fullMatchForString(String pathSegment) {
    var iter = matchRegex.allMatches(pathSegment).iterator;
    if (iter.moveNext()) {
      var match = iter.current;
      if(match.start == 0 && match.end == pathSegment.length && !iter.moveNext()) {
        return true;
      } else {
        return false;
      }
    }

    return false;
  }

  String toString() {
    String str = "${matchesRemaining} ${name} ";
    if(matchRegex != null) {
      str = str + matchRegex.pattern;
    }
    return str;
  }

}