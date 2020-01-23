import 'dart:io';

import 'package:meta/meta.dart';

void copyDirectory({@required Uri src, @required Uri dst}) {
  final srcDir = Directory.fromUri(src);
  final dstDir = Directory.fromUri(dst);
  if (!dstDir.existsSync()) {
    dstDir.createSync();
  }

  srcDir.listSync().forEach((fse) {
    if (fse is File) {
      final outPath = dstDir.uri
        .resolve(fse.uri.pathSegments.last)
        .toFilePath(windows: Platform.isWindows);
      fse.copySync(outPath);
    } else if (fse is Directory) {
      final segments = fse.uri.pathSegments;
      final outPath = dstDir.uri.resolve(segments[segments.length - 2]);
      copyDirectory(src: fse.uri, dst: outPath);
    }
  });
}