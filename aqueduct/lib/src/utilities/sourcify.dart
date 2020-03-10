String sourcifyValue(dynamic v, {String onError}) {
  if (v is String) {
    if (v == null) {
      return "null";
    }
    if (!v.contains("'")) {
      return "'$v'";
    }
    if (!v.contains('"')) {
      return '"$v"';
    }

    // todo: not urgent
    throw StateError("${onError ?? "A string literal contains both a single and double quote"}. "
      "This is not yet implemented - please submit a pull request.");
  }

  return "$v";
}