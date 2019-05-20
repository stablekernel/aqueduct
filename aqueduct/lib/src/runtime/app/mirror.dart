import 'dart:async';
import 'dart:isolate';
import 'dart:mirrors';
import 'package:aqueduct/src/application/application.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/application/isolate_application_server.dart';
import 'package:aqueduct/src/application/isolate_supervisor.dart';
import 'package:aqueduct/src/application/options.dart';
import 'package:aqueduct/src/http/serializable.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct/src/runtime/app/app.dart';
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


class ControllerRuntimeImpl extends ControllerRuntime {
  ControllerRuntimeImpl(Type t) : type = reflectClass(t);

  final ClassMirror type;

  @override
  bool get isMutable {
    // We have a whitelist for a few things declared in controller that can't be final.
    final whitelist = ['policy=', '_nextController='];
    final members = type.instanceMembers;
    final fieldKeys = type.instanceMembers.keys
      .where((sym) => !whitelist.contains(MirrorSystem.getName(sym)));
    return fieldKeys.any((key) => members[key].isSetter);
  }
}

class SerializableRuntimeImpl extends SerializableRuntime {
  SerializableRuntimeImpl(Type t) : type = reflectClass(t);

  final ClassMirror type;

  @override
  APISchemaObject documentSchema(APIDocumentContext context) {
    final mirror = type;

    final obj = APISchemaObject.object({})
      ..title = MirrorSystem.getName(mirror.simpleName);
    try {
      for (final property
      in mirror.declarations.values.whereType<VariableMirror>()) {
        final propName = MirrorSystem.getName(property.simpleName);
        obj.properties[propName] = documentVariable(context, property);
      }
    } catch (e) {
      obj.additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      obj.description =
      "Failed to auto-document type '${MirrorSystem.getName(mirror.simpleName)}': ${e.toString()}";
    }

    return obj;
  }

  static APISchemaObject documentVariable(
    APIDocumentContext context, VariableMirror mirror) {
    APISchemaObject object = documentType(context, mirror.type)
      ..title = MirrorSystem.getName(mirror.simpleName);

    return object;
  }

  static APISchemaObject documentType(
    APIDocumentContext context, TypeMirror type) {
    if (type.isAssignableTo(reflectType(int))) {
      return APISchemaObject.integer();
    } else if (type.isAssignableTo(reflectType(double))) {
      return APISchemaObject.number();
    } else if (type.isAssignableTo(reflectType(String))) {
      return APISchemaObject.string();
    } else if (type.isAssignableTo(reflectType(bool))) {
      return APISchemaObject.boolean();
    } else if (type.isAssignableTo(reflectType(DateTime))) {
      return APISchemaObject.string(format: "date-time");
    } else if (type.isAssignableTo(reflectType(List))) {
      return APISchemaObject.array(
        ofSchema: documentType(context, type.typeArguments.first));
    } else if (type.isAssignableTo(reflectType(Map))) {
      if (!type.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw ArgumentError("Unsupported type 'Map' with non-string keys.");
      }
      return APISchemaObject()
        ..type = APIType.object
        ..additionalPropertySchema =
        documentType(context, type.typeArguments.last);
    } else if (type.isAssignableTo(reflectType(Serializable))) {
      final instance = (type as ClassMirror).newInstance(const Symbol(''), []).reflectee as Serializable;
      return instance.documentSchema(context);
    }

    throw ArgumentError(
      "Unsupported type '${MirrorSystem.getName(type.simpleName)}' for 'APIComponentDocumenter.documentType'.");
  }
}