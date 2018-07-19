import 'package:matcher/matcher.dart';
import 'matchers.dart';

/// A test matcher that matches an HTTP response body.
///
/// See [hasBody] or [hasResponse] for more details.
class HTTPBodyMatcher extends Matcher {
  HTTPBodyMatcher(dynamic matcher) {
    if (matcher is Matcher) {
      contentMatcher = matcher;
    } else {
      contentMatcher = equals(matcher);
    }
  }

  Matcher contentMatcher;

  @override
  bool matches(dynamic item, Map matchState) {
    if (!contentMatcher.matches(item, matchState)) {
      return false;
    }

    return true;
  }

  @override
  Description describe(Description description) {
    description.add("- Body after decoding must be:\n\n  ");
    description.addDescriptionOf(contentMatcher);

    return description;
  }

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
      Map matchState, bool verbose) {
    mismatchDescription.add("the body differs for the following reasons:\n");

    contentMatcher.describeMismatch(
        item, mismatchDescription, matchState, verbose);

    return mismatchDescription;
  }
}
