import 'dart:io';
import 'package:path/path.dart' as path_lib;


void main(List<String> args) {
  var testDirectory = new Directory(path_lib.relative("test",
      from: Directory.current.path));

  var allTestFiles = testFilesFromDirectory(testDirectory)
    .map((f) => path_lib.relative(f.path, from: testDirectory.path))
    .toList();

  var buf = new StringBuffer();

  buf.writeln("import 'package:test/test.dart';");
  allTestFiles.forEach((filename) {
    buf.writeln("import '$filename' as ${prefixForFilename(filename)};");
  });

  buf.writeln("");
  buf.writeln("void main() {");
  allTestFiles.forEach((filename) {
    buf.writeln("\tgroup('$filename', ${prefixForFilename(filename)}.main);");
  });
  buf.writeln("}");

  var outPath = path_lib.join(testDirectory.absolute.path, args.first);
  var outFile = new File(outPath);
  outFile.writeAsStringSync(buf.toString());
}

String prefixForFilename(String filename) {
  return path_lib
      .split(filename)
      .join("_")
      .split(".dart")
      .first;
}

List<File> testFilesFromDirectory(Directory dir) {
  var entries = dir.listSync();
  var files = entries
      .where((fse) => fse is File)
      .where((fse) => fse.path.endsWith("_test.dart"))
      .map((fse) => fse as File)
      .toList();

  var subdirectoryFiles = entries
    .where((fse) => fse is Directory)
    .map((dir) => testFilesFromDirectory(dir))
    .expand((files) => files)
    .toList();

  subdirectoryFiles.addAll(files);

  return subdirectoryFiles;
}