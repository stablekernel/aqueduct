import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/utilities/file_system.dart';
import 'package:meta/meta.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class RuntimeLinker {
  RuntimeLinker(
      {@required this.srcProjectUri,
      @required this.runtimeLoaderUri,
      @required List<String> dependencies}) {
    final map = _packagesMap;
    _dependencies =
        Map.fromEntries(dependencies.map((d) => MapEntry(d, map[d])));
  }

  final Uri srcProjectUri;
  final Uri runtimeLoaderUri;
  Map<String, Uri> _dependencies;

  Map<String, Uri> get _packagesMap {
    final packagesFile = File.fromUri(srcProjectUri.resolve(".packages"));
    return Map.fromEntries(packagesFile
        .readAsStringSync()
        .split("\n")
        .where((s) => !s.trimLeft().startsWith("#"))
        .where((s) => s.trim().isNotEmpty)
        .map((s) {
      final packageName = s.substring(0, s.indexOf(":"));
      final uri = Uri.parse(s.substring("$packageName:".length));
      if (uri.isAbsolute) {
        return MapEntry(packageName, Directory.fromUri(uri).parent.uri);
      }
      return MapEntry(
          packageName,
          Directory.fromUri(srcProjectUri.resolveUri(uri).normalizePath())
              .parent
              .uri);
    }));
  }

  Future<void> link(Uri outputUri) async {
    final packagesDir = Directory.fromUri(outputUri.resolve("packages/"));
    final projectDir = Directory.fromUri(outputUri.resolve("app/"));

    if (packagesDir.existsSync()) {
      packagesDir.deleteSync(recursive: true);
    }
    if (projectDir.existsSync()) {
      projectDir.deleteSync(recursive: true);
    }

    packagesDir.createSync(recursive: true);
    projectDir.createSync(recursive: true);

    _copyDependencies(packagesDir.uri);
    _copyProject(projectDir.uri);
  }

  void _copyDependencies(Uri dstPackagesUri) {
    _dependencies.forEach((name, location) {
      final packageUri = dstPackagesUri.resolve("$name/");
      final sourceDir = Directory.fromUri(packageUri);
      sourceDir.createSync(recursive: true);

      final pubspecFile = File.fromUri(location.resolve("pubspec.yaml"))
          .copySync(packageUri
              .resolve("pubspec.yaml")
              .toFilePath(windows: Platform.isWindows));

      final pubspec = Pubspec.parse(pubspecFile.readAsStringSync());
      final pubspecMap = _getPubspecMap(pubspec);
      pubspecFile.writeAsStringSync(json.encode(pubspecMap));

      copyDirectory(
          src: location.resolve("lib/"), dst: packageUri.resolve("lib/"));

      final frameworkRuntimeFile = File.fromUri(packageUri
          .resolve("lib/")
          .resolve("src/")
          .resolve("runtime/")
          .resolve("runtime.dart"));
      if (!frameworkRuntimeFile.existsSync()) {
        throw ArgumentError(
            "Package '$name' has no runtime file. expected the file 'lib/src/runtime/runtime.dart' in '$packageUri'");
      }

      const replacementLine = "import 'loader.dart' as loader;";
      final frameworkRuntimeContents = frameworkRuntimeFile.readAsStringSync();
      if (!frameworkRuntimeContents.contains(replacementLine)) {
        throw ArgumentError(
            "The runtime for package '$name' is invalid. It must contain the directive: 'import 'loader.dart' as loader;'");
      }
      frameworkRuntimeFile.writeAsStringSync(
          frameworkRuntimeContents.replaceFirst(
              replacementLine, "import '$runtimeLoaderUri' as loader;"));
    });
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
      overrides[name] = {"path": uri.toFilePath(windows: Platform.isWindows)};
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
