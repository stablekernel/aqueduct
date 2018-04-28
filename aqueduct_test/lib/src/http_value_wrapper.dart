import 'dart:io';

import 'package:matcher/matcher.dart';

class HTTPValueMatcherWrapper extends Matcher {
  HTTPValueMatcherWrapper(dynamic matcherOrValue) {
    if (matcherOrValue is! Matcher) {
      _matcher = equals(matcherOrValue);
    } else {
      _matcher = matcherOrValue;
    }
  }

   Matcher _matcher;

  @override
  bool matches(dynamic item, Map matchState) {
    // Try as just a String first. If that fails, see if we can parse it as anything
    // If we can, try that one.

    var tempMatchState = {};
    try {
      if (_matcher.matches(item, tempMatchState)) {
        matchState.addAll(tempMatchState);
        return true;
      }
    } catch (_) {
      // If the initial value can't be compared to string, then we catch this
      // and move on to trying to parse
    }

    if (item == null) {
      matchState.addAll(tempMatchState);
      return false;
    }

    var v;
    try {
      v = num.parse(item);
      matchState["HTTPValueWrapper.parsedAs"] = num;
    } on FormatException {}
    try {
      v = HttpDate.parse(item);
      matchState["HTTPValueWrapper.parsedAs"] = HttpDate;
    } on FormatException {
    } on HttpException {}

    try {
      v = DateTime.parse(item);
      matchState["HTTPValueWrapper.parsedAs"] = DateTime;
    } on FormatException {}

    if (v == null) {
      matchState.addAll(tempMatchState);
      return false;
    }

    return _matcher.matches(v, matchState);
  }

  @override
  Description describe(Description description) {
    return description.addDescriptionOf(_matcher);
  }

  @override
  Description describeMismatch(
      dynamic item, Description mismatchDescription, Map matchState, bool verbose) {
    var parsedAs = matchState["HTTPValueWrapper.parsedAs"];
    if (parsedAs != null) {
      item = parsedAs.parse(item);
    }

    _matcher.describeMismatch(item, mismatchDescription, matchState, verbose);

    return mismatchDescription;
  }
}