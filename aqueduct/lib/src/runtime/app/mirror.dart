import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';
import 'package:aqueduct/src/application/application.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/application/isolate_application_server.dart';
import 'package:aqueduct/src/application/isolate_supervisor.dart';
import 'package:aqueduct/src/application/options.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/runtime/app/channel.dart';
import 'package:logging/logging.dart';

class ChannelRuntimeImpl extends ChannelRuntime {
  ChannelRuntimeImpl(Type type) : type = reflectClass(type);

  final ClassMirror type;

  @override
  Type get channelType => type.reflectedType;

  @override
  ApplicationChannel instantiateChannel() {
    return type.newInstance(Symbol.empty, []).reflectee as ApplicationChannel;
  }

  @override
  Future runGlobalInitialization(ApplicationOptions config) {
    const globalStartSymbol = #initializeApplication;
    if (type.staticMembers[globalStartSymbol] != null) {
      return type.invoke(globalStartSymbol, [config]).reflectee as Future;
    }

    return null;
  }

  @override
  Future<ApplicationIsolateSupervisor> spawn(
      Application application,
      ApplicationOptions config,
      int identifier,
      Logger logger,
      Duration startupTimeout,
      {bool logToConsole = false}) async {
    final receivePort = ReceivePort();

    final streamLibraryURI = (type.owner as LibraryMirror).uri;
    final streamTypeName = MirrorSystem.getName(type.simpleName);

    final initialMessage = ApplicationInitialServerMessage(streamTypeName,
        streamLibraryURI, config, identifier, receivePort.sendPort,
        logToConsole: logToConsole);
    final isolate = await Isolate.spawn(isolateServerEntryPoint, initialMessage,
        paused: true);

    return ApplicationIsolateSupervisor(
        application, isolate, receivePort, identifier, logger,
        startupTimeout: startupTimeout);
  }

  @override
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(ApplicationChannel channel) {
    final documenter = reflectType(APIComponentDocumenter);
    return type.declarations.values
        .whereType<VariableMirror>()
        .where((member) =>
            !member.isStatic && member.type.isAssignableTo(documenter))
        .map((dm) {
      return reflect(channel).getField(dm.simpleName).reflectee
          as APIComponentDocumenter;
    }).where((o) => o != null);
  }
}

void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  final channelSourceLibrary =
      currentMirrorSystem().libraries[params.streamLibraryURI];
  final channelType = channelSourceLibrary
      .declarations[Symbol(params.streamTypeName)] as ClassMirror;

  final runtime = ChannelRuntimeImpl(channelType.reflectedType);

  final server = ApplicationIsolateServer(runtime.channelType, params.configuration,
      params.identifier, params.parentMessagePort,
      logToConsole: params.logToConsole);

  server.start(shareHttpServer: true);
}
