part of monadart;

/// A representation of a Route match, containing the elements of the matched path.
///
/// Instances of this class can be used by handlers after the router to inspect
/// specifics of the incoming path without having to dissect the path on their own.
class ResourcePatternMatch {
  /// A map of variable to values in this match.
  ///
  /// If a path has variables (indicated by the :name syntax) in the path,
  /// the matching segments for the path will be stored in the map. The key
  /// will be the variable name (without the colon) and the value will be the
  /// path segment as a string.
  ///
  /// Example:
  /// Consider a match specification /users/:id. If the evaluated path is
  ///     /users/2
  /// This property will be {'id' : '2'}.
  ///
  Map<String, String> variables = {};

  /// A list of the segments in a matched path.
  ///
  /// This property will contain every segment of the matched path, including
  /// constant segments. It will not contain any part of the path caught by
  /// the asterisk 'match all' token, however. Those are in [remainingPath].
  List<String> segments = [];

  /// If a match specification uses the asterisk 'match all' token,
  /// the part of the path matched by that token will be stored in this property.
  ///
  /// The remaining path will will be a single string, including any path delimeters (/),
  /// but will not have a leading path delimeter.
  String remainingPath;
}

class ResourcePattern {
  static String remainingPath = "remainingPath";

  _ResourcePatternSet matchHead;

  ResourcePattern(String patternString) {
    List<String> pathElements = splitPattern(patternString);

    List<_ResourcePatternElement> elems =
        resourceElementsFromPathElements(patternString);

    matchHead = matchSpecFromElements(pathElements, elems);
  }

  static _ResourcePatternSet matchSpecFromElements(List<String> pathElements,
      List<_ResourcePatternElement> resourceElements) {
    // These two arrays should be identical in size by the time they get here

    _ResourcePatternSet setHead = new _ResourcePatternSet();
    _ResourcePatternSet setPtr = setHead;

    for (int i = 0; i < pathElements.length; i++) {
      String seg = pathElements[i];

      if (seg.startsWith("[")) {
        _ResourcePatternSet set = new _ResourcePatternSet();
        setPtr.nextOptionalSet = set;

        setPtr = set;
      }

      setPtr.addElement(resourceElements[i]);

      for (int i = seg.length - 1; i >= 0; i--) {
        if (seg[i] == "]") {
          setPtr = setPtr.parentSet;
        } else {
          break;
        }
      }
    }

    if (setPtr != setHead) {
      throw new ArgumentError("unmatched brackets in optional paths");
    }

    return setHead;
  }

  static List<String> splitPattern(String patternString) {
    return patternString.split("/").fold(new List<String>(),
        (List<String> accum, String e) {
      var trimmed = e.trim();
      if (trimmed.length > 0) {
        accum.add(trimmed);
      }
      return accum;
    });
  }

  static List<_ResourcePatternElement> resourceElementsFromPathElements(
      String patternString) {
    var expr = new RegExp(r"[\[\]]");
    return splitPattern(patternString)
        .map((segment) =>
            new _ResourcePatternElement(segment.replaceAll(expr, "")))
        .toList();
  }

  ResourcePatternMatch matchUri(Uri uri) {
    ResourcePatternMatch match = new ResourcePatternMatch();

    var incomingPathSegments = uri.pathSegments;
    var incomingPathIndex = 0;
    var resourceSet = matchHead;
    var resourceIterator = resourceSet.elements.iterator;

    while (resourceSet != null) {
      while (resourceIterator.moveNext()) {
        // If we run into a *, then we're definitely a match so just grab the end of the path and return it.

        var resourceSegment = resourceIterator.current;
        if (resourceSegment.matchesRemaining) {
          var remainingString = incomingPathSegments
              .sublist(incomingPathIndex, incomingPathSegments.length)
              .join("/");
          match.remainingPath = remainingString;

          return match;
        } else {
          // If we're out of path segments, then we don't match
          if (incomingPathIndex >= incomingPathSegments.length) {
            return null;
          }

          var pathSegment = incomingPathSegments[incomingPathIndex];
          incomingPathIndex++;

          bool matches = resourceSegment.fullMatchForString(pathSegment);
          if (!matches) {
            // There was a path segment available, but it did not match
            return null;
          }

          // We match!
          if (resourceSegment.name != null) {
            match.variables[resourceSegment.name] = pathSegment;
          }

          match.segments.add(pathSegment);
        }
      }
      resourceSet = resourceSet.nextOptionalSet;

      // If we have path remaining, then we either have optional left or we don't have a match
      if (incomingPathIndex < incomingPathSegments.length) {
        if (resourceSet == null) {
          return null;
        } else {
          resourceIterator = resourceSet.elements.iterator;
        }
      }
    }

    return match;
  }
}

class _ResourcePatternSet {
  List<_ResourcePatternElement> elements = [];

  _ResourcePatternSet parentSet;
  _ResourcePatternSet _nextOptionalSet;
  _ResourcePatternSet get nextOptionalSet => _nextOptionalSet;
  void set nextOptionalSet(_ResourcePatternSet s) {
    _nextOptionalSet = s;
    s.parentSet = this;
  }

  void addElement(_ResourcePatternElement e) {
    elements.add(e);
  }
}

class _ResourcePatternElement {
  bool matchesRemaining = false;
  String name;
  RegExp matchRegex;

  _ResourcePatternElement(String segment) {
    if (segment.startsWith(":")) {
      var contents = segment.substring(1, segment.length);
      constructFromString(contents);
    } else if (segment == "*") {
      matchesRemaining = true;
    } else {
      matchRegex = new RegExp(segment);
    }
  }

  // I'd prefer that this used a outer non-capturing group on the parantheses after the name;
  // but apparently this regex parser won't pick up the capture group inside the noncapturing group for some reason
  static RegExp patternFinder =
      new RegExp(r"^(\w+)(\(([^\)]+)\))?$", caseSensitive: false);

  void constructFromString(String str) {
    Match m = patternFinder.firstMatch(str);
    if (m == null) {
      throw new ArgumentError(
          "invalid resource pattern segment ${str}, available formats are the following: literal, *, {name}, {name(pattern)}");
    }

    name = m.group(1);

    var matchString = ".+";
    if (m.groupCount == 3) {
      if (m.group(2) != null) {
        matchString = m.group(2);
      }
    }

    matchRegex =
        new RegExp(r"^" + "${matchString}" + r"$", caseSensitive: false);
  }

  bool fullMatchForString(String pathSegment) {
    var iter = matchRegex.allMatches(pathSegment).iterator;
    if (iter.moveNext()) {
      var match = iter.current;
      if (match.start == 0 &&
          match.end == pathSegment.length &&
          !iter.moveNext()) {
        return true;
      } else {
        return false;
      }
    }

    return false;
  }

  String toString() {
    String str = "${matchesRemaining} ${name} ";
    if (matchRegex != null) {
      str = str + matchRegex.pattern;
    }
    return str;
  }
}
