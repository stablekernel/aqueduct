import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aqueduct/src/utilities/file_system.dart';
import 'package:meta/meta.dart';
import 'package:pubspec_parse/pubspec_parse.dart';

class RuntimeLinker {
  RuntimeLinker(this.srcProjectUri, this.runtimeLoaderUri,
      {this.srcFrameworkUri}) {
    if (srcFrameworkUri == null) {
      final packagesFile = File.fromUri(srcProjectUri.resolve(".packages"));
      final aqueductPath = packagesFile
          .readAsStringSync()
          .split("\n")
          .firstWhere((line) => line.startsWith("aqueduct:"))
          .substring("aqueduct:".length);

      final aqueductUri = Uri.parse(aqueductPath);
      if (aqueductUri.isAbsolute) {
        srcFrameworkUri = Directory.fromUri(aqueductUri).parent.uri;
      } else {
        srcFrameworkUri = Directory.fromUri(srcProjectUri.resolveUri(aqueductUri).normalizePath()).parent.uri;
      }
    }
  }

  final Uri srcProjectUri;
  final Uri runtimeLoaderUri;
  Uri srcFrameworkUri;

  Future<void> link(Uri outputUri) async {
    final frameworkDir = Directory.fromUri(outputUri.resolve("framework/"));
    final projectDir = Directory.fromUri(outputUri.resolve("app/"));

    frameworkDir.createSync(recursive: true);
    projectDir.createSync(recursive: true);

    _copyFramework(frameworkDir.uri);
    _copyProject(projectDir.uri, frameworkUri: frameworkDir.uri);
  }
  
  void _copyFramework(Uri dstFrameworkUri) {
    File.fromUri(srcFrameworkUri.resolve("pubspec.yaml")).copySync(dstFrameworkUri
      .resolve("pubspec.yaml")
      .toFilePath(windows: Platform.isWindows));

    final pubpsecFile = File.fromUri(dstFrameworkUri.resolve("pubspec.yaml"));
    final pubspec = Pubspec.parse(pubpsecFile.readAsStringSync());
    final pubspecMap = <String, dynamic>{};
    pubspecMap['environment'] = pubspec.environment.map((k, v) => MapEntry(k, v.toString()));
    pubspecMap['name'] = pubspec.name;
    pubspecMap['version'] = pubspec.version.toString();
    pubspecMap['dependencies'] = pubspec.dependencies.map((n, d) => MapEntry(n, _getDependencyValue(d)));
    pubspecMap['dependency_overrides'] = pubspec.dependencyOverrides.map((n, d) => MapEntry(n, _getDependencyValue(d)));
    pubpsecFile.writeAsStringSync(json.encode(pubspecMap));
    
    copyDirectory(
      src: srcFrameworkUri.resolve("lib/"),
      dst: dstFrameworkUri.resolve("lib/"));
    
    final frameworkRuntimeFile = File.fromUri(dstFrameworkUri
        .resolve("lib/")
        .resolve("src/")
        .resolve("runtime/")
        .resolve("runtime.dart"));
    final frameworkRuntimeContents = frameworkRuntimeFile.readAsStringSync();
    frameworkRuntimeFile.writeAsStringSync(
        frameworkRuntimeContents.replaceFirst("import 'loader.dart' as loader;",
            "import '$runtimeLoaderUri' as loader;"));
  }

  void _copyProject(Uri dstProjectUri, {@required Uri frameworkUri}) {
    File.fromUri(srcProjectUri.resolve("pubspec.yaml")).copySync(dstProjectUri
      .resolve("pubspec.yaml")
      .toFilePath(windows: Platform.isWindows));
    File.fromUri(srcProjectUri.resolve("pubspec.lock")).copySync(dstProjectUri
      .resolve("pubspec.lock")
      .toFilePath(windows: Platform.isWindows));
    copyDirectory(
      src: srcProjectUri.resolve("lib/"),
      dst: dstProjectUri.resolve("lib/"));
    
    final pubpsecFile = File.fromUri(dstProjectUri.resolve("pubspec.yaml"));
    final pubspec = Pubspec.parse(pubpsecFile.readAsStringSync());
    final pubspecMap = <String, dynamic>{};
    pubspecMap['name'] = pubspec.name;
    pubspecMap['version'] = pubspec.version.toString();
    pubspecMap['environment'] = pubspec.environment.map((k, v) => MapEntry(k, v.toString()));
    final deps = pubspecMap['dependencies'] = <String, dynamic>{};
    final overrides = pubspecMap['dependency_overrides'] = <String, dynamic>{};

    pubspec.dependencies.forEach((name, dep) {
      if (name == "aqueduct") {
        deps[name] = {"path": frameworkUri.path};
      } else {
        deps[name] = _getDependencyValue(dep);
      }
    });

    pubspec.dependencyOverrides.forEach((name, dep) {
      if (name == "aqueduct") {
        overrides[name] = {"path": frameworkUri.path};
      } else {
        overrides[name] = _getDependencyValue(dep);
      }
    });

    pubpsecFile.writeAsStringSync(json.encode(pubspecMap));
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
