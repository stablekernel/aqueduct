import 'dart:async';

import 'package:aqueduct/src/application/application.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/application/isolate_supervisor.dart';
import 'package:aqueduct/src/application/options.dart';
import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:logging/logging.dart';

abstract class ChannelRuntime {
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(ApplicationChannel channel);
  Type get channelType;
  ApplicationChannel instantiateChannel();
  Future runGlobalInitialization(ApplicationOptions config);
  Future<ApplicationIsolateSupervisor> spawn(Application application, ApplicationOptions config, int identifier, Logger logger, Duration startupTimeout,
    {bool logToConsole = false});
}
