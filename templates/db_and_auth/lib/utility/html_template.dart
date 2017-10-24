import 'dart:io';
import 'dart:async';

class HTMLRenderer {
  Map<String, String> _cache = {};

  Future<String> renderHTML(
      String path, Map<String, dynamic> templateVariables) async {
    var template = await _loadHTMLTemplate(path);

    return template.replaceAllMapped(new RegExp("{{([a-zA-Z_]+)}}"), (match) {
      var key = match.group(1);
      return templateVariables[key] ?? "null";
    });
  }

  Future<String> _loadHTMLTemplate(String path) async {
    var contents = _cache[path];
    if (contents == null) {
      try {
        var file = new File(path);
        contents = file.readAsStringSync();
        _cache[path] = contents;
      } catch (_) {}
    }

    return contents;
  }
}
