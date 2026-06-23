import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the foreground-service isolate. Must be top-level and kept
/// by the tree-shaker, hence the vm:entry-point pragma.
@pragma('vm:entry-point')
void startTripTaskCallback() {
  FlutterForegroundTask.setTaskHandler(TripTaskHandler());
}

/// Runs in the service isolate. It holds no trip state — the recorder lives in
/// the main isolate — so it just relays the notification button taps back to
/// the main isolate, which drives pause/resume/stop on the recorder.
class TripTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onNotificationButtonPressed(String id) {
    FlutterForegroundTask.sendDataToMain({'action': id});
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
