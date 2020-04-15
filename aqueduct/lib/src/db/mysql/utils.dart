class MySqlUtils {
  static List<dynamic> getMySqlVariables(
      String sql, Map<String, dynamic> variables) {
    assert(sql != null);
    if (variables == null || variables.isEmpty) {
      return null;
    }
    RegExp regExp = RegExp(r'\?\/\*([^\*+?]+)\*\/');
    Iterable<Match> matchs = regExp.allMatches(sql);
    if (matchs == null || matchs.isEmpty) {
      return null;
    }
    List<dynamic> params = [];
    for (Match m in matchs) {
      String match = m.group(1);
      if (variables.containsKey(match)) {
        params.add(variables[match]);
      } else {
        params.add(null);
      }
    }
    return params;
  }
}
