import 'dart:async';
import 'dart:io';

typedef Future _StopProcess(String reason);

class StoppableProcess {
  StoppableProcess(Future onStop(String reason)) : _stop = onStop {
    var l1 = ProcessSignal.SIGINT.watch().listen((_) {
      stop(0, reason: "Process interrupted.");
    });

    var l2 = ProcessSignal.SIGTERM.watch().listen((_) {
      stop(0, reason: "Process terminated by OS.");
    });

    _listeners = [l1, l2];
  }

  Future<int> get exitCode => _completer.future;

  List<StreamSubscription> _listeners;

  final _StopProcess _stop;
  final Completer<int> _completer = new Completer<int>();

  Future stop(int exitCode, {String reason}) async {
    if (_completer.isCompleted) {
      return;
    }

    await Future.forEach(_listeners, (StreamSubscription sub) => sub.cancel());
    await _stop(reason);
    _completer.complete(exitCode);
  }
}
