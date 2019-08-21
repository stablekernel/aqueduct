import 'package:runtime/runtime.dart';
import 'package:crypto/crypto.dart';

class MigrationSource {
  MigrationSource(this.source, this.uri, int nameStartIndex, int nameEndIndex) {
    originalName = source.substring(nameStartIndex, nameEndIndex);
    name = "M${md5.convert(source.codeUnits).toString()}";
    source = source.replaceRange(nameStartIndex, nameEndIndex, name);
  }

  MigrationSource.fromMap(Map<String, dynamic> map) {
    originalName = map["originalName"] as String;
    source = map["source"] as String;
    name = map["name"] as String;
    uri = map["uri"] as Uri;
  }

  factory MigrationSource.fromFile(Uri uri) {
    final analyzer = CodeAnalyzer(uri);
    final migrationTypes = analyzer.getSubclassesFromFile("Migration", uri);
    if (migrationTypes.length != 1) {
      throw StateError(
        "Invalid migration file. Must contain exactly one 'Migration' subclass. File: '$uri'.");
    }

    final klass = migrationTypes.first;
    final source = klass.toSource();
    final offset = klass.name.offset - klass.offset;
    return MigrationSource(source, uri, offset, offset + klass.name.length);
  }

  Map<String, dynamic> asMap() {
    return {
      "originalName": originalName,
      "name": name,
      "source": source,
      "uri": uri
    };
  }

  static String combine(List<MigrationSource> sources) {
    return sources.map((s) => s.source).join("\n");
  }

  static int versionNumberFromUri(Uri uri) {
    var fileName = uri.pathSegments.last;
    var migrationName = fileName.split(".").first;
    return int.parse(migrationName.split("_").first);
  }

  String source;

  String originalName;

  String name;

  Uri uri;

  int get versionNumber => versionNumberFromUri(uri);
}
