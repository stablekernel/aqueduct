import 'dart:io';

import 'package:matcher/matcher.dart';

class HTTPValueMatcherWrapper extends Matcher {
  HTTPValueMatcherWrapper(this._matcher);

  final Matcher _matcher;

  @override
  bool matches(dynamic item, Map matchState) {
    // Try as just a String first. If that fails, see if we can parse it as anything
    // If we can, try that one.

    final tempMatchState = {};
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

    if (item is! String) {
      throw StateError("Header response value is not a String.");
    }

    final onSuccess = (v) {
      if (v == null) {
        matchState.addAll(tempMatchState);
        return false;
      }
      return _matcher.matches(v, matchState);
    };

    try {
      return onSuccess(num.parse(item as String));
      // ignore: empty_catches
    } on FormatException {}

    try {
      return onSuccess(HttpDate.parse(item as String));
      // ignore: empty_catches
    } on FormatException {} on HttpException {}

    try {
      return onSuccess(DateTime.parse(item as String));
      // ignore: empty_catches
    } on FormatException {}

    return false;
  }

  @override
  Description describe(Description description) {
    return description.addDescriptionOf(_matcher);
  }

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    _matcher.describeMismatch(item, mismatchDescription, matchState, verbose);

    return mismatchDescription;
  }
}
