import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/utilities/file_system.dart';
import 'package:meta/meta.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class RuntimeLinker {
  RuntimeLinker(this.srcProjectUri, this.runtimeLoaderUri,
      {Map<String, Uri> dependencies}) {
    _dependencies = dependencies ?? {};
    if (!_dependencies.containsKey("aqueduct")) {
      final packagesFile = File.fromUri(srcProjectUri.resolve(".packages"));
      final aqueductPath = packagesFile
          .readAsStringSync()
          .split("\n")
          .firstWhere((line) => line.startsWith("aqueduct:"))
          .substring("aqueduct:".length);

      final aqueductUri = Uri.parse(aqueductPath);
      if (aqueductUri.isAbsolute) {
        _dependencies["aqueduct"] = Directory.fromUri(aqueductUri).parent.uri;
      } else {
        _dependencies["aqueduct"] = Directory.fromUri(
                srcProjectUri.resolveUri(aqueductUri).normalizePath())
            .parent
            .uri;
      }
    }
  }

  final Uri srcProjectUri;
  final Uri runtimeLoaderUri;
  Map<String, Uri> _dependencies;

  Future<void> link(Uri outputUri) async {
    final packagesDir = Directory.fromUri(outputUri.resolve("packages/"));
    final projectDir = Directory.fromUri(outputUri.resolve("app/"));

    packagesDir.createSync(recursive: true);
    projectDir.createSync(recursive: true);

    _copyDependencies(packagesDir.uri);
    _copyProject(projectDir.uri);
  }

  void _copyDependencies(Uri dstPackagesUri) {
    _dependencies.forEach((name, location) {
      final packageUri = dstPackagesUri.resolve("$name/");
      final dir = Directory.fromUri(packageUri);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      dir.createSync(recursive: true);

      final pubspecFile = File.fromUri(location.resolve("pubspec.yaml"))
          .copySync(packageUri
              .resolve("pubspec.yaml")
              .toFilePath(windows: Platform.isWindows));

      final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
      final pubspecMap = _getPubspecMap(pubspec);
      pubspecFile.writeAsStringSync(json.encode(pubspecMap));

      copyDirectory(
          src: location.resolve("lib/"), dst: packageUri.resolve("lib/"));
    });

    /*
     this should only happen for aqueduct package.
     there should be some sort of mechanism for 'linking' a package
     on a per-package basis
      */

    final frameworkRuntimeFile = File.fromUri(dstPackagesUri
        .resolve("lib/")
        .resolve("src/")
        .resolve("runtime/")
        .resolve("runtime.dart"));
    final frameworkRuntimeContents = frameworkRuntimeFile.readAsStringSync();
    frameworkRuntimeFile.writeAsStringSync(
        frameworkRuntimeContents.replaceFirst("import 'loader.dart' as loader;",
            "import '$runtimeLoaderUri' as loader;"));
  }

  void _copyProject(Uri dstProjectUri) {
    File.fromUri(srcProjectUri.resolve("pubspec.yaml")).copySync(dstProjectUri
        .resolve("pubspec.yaml")
        .toFilePath(windows: Platform.isWindows));
    File.fromUri(srcProjectUri.resolve("pubspec.lock")).copySync(dstProjectUri
        .resolve("pubspec.lock")
        .toFilePath(windows: Platform.isWindows));
    copyDirectory(
        src: srcProjectUri.resolve("lib/"), dst: dstProjectUri.resolve("lib/"));

    final pubpsecFile = File.fromUri(dstProjectUri.resolve("pubspec.yaml"));
    final pubspec = Pubspec.parse(pubpsecFile.readAsStringSync());
    final pubspecMap = _getPubspecMap(pubspec);

    final overrides = pubspecMap['dependency_overrides'];
    _dependencies.forEach((name, uri) {
      overrides[name] = {"path": uri};
    });
    pubpsecFile.writeAsStringSync(json.encode(pubspecMap));
  }

  Map<String, dynamic> _getPubspecMap(Pubspec pubspec) {
    final pubspecMap = <String, dynamic>{};
    pubspecMap['name'] = pubspec.name;
    pubspecMap['version'] = pubspec.version.toString();
    pubspecMap['environment'] =
        pubspec.environment.map((k, v) => MapEntry(k, v.toString()));
    pubspecMap['dependencies'] =
        pubspec.dependencies.map((n, d) => MapEntry(n, _getDependencyValue(d)));
    pubspecMap['dependency_overrides'] = pubspec.dependencyOverrides
        .map((n, d) => MapEntry(n, _getDependencyValue(d)));
    return pubspecMap;
  }

  dynamic _getDependencyValue(Dependency dep) {
    if (dep is PathDependency) {
      final uri = Uri.parse(dep.path);
      final normalized = srcProjectUri.resolveUri(uri).normalizePath();
      return {"path": normalized.path};
    } else if (dep is HostedDependency) {
      if (dep.hosted == null) {
        return "${dep.version}";
      } else {
        return {
          "hosted": {"name": dep.hosted.name, "url": dep.hosted.url}
        };
      }
    } else if (dep is GitDependency) {
      final m = {"git": <String, dynamic>{}};
      final inner = m["git"];

      if (dep.url != null) {
        inner["url"] = dep.url.toString();
      }

      if (dep.path != null) {
        inner["path"] = dep.path;
      }

      if (dep.ref != null) {
        inner["ref"] = dep.ref;
      }

      return m;
    } else {
      throw StateError('unexpected dependency type');
    }
  }
}
