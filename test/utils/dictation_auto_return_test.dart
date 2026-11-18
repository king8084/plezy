import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/dictation_auto_return.dart';

void main() {
  test('a spoken phrase returns after a quiet second; typing does not', () {
    fakeAsync((async) {
      final controller = TextEditingController();
      var returned = 0;
      final watcher = DictationAutoReturn(controller: controller, onSpoken: () => returned++)..start();

      controller.text = 'm';
      controller.text = 'mo';
      async.elapse(const Duration(seconds: 3));
      expect(returned, 0, reason: 'one character at a time is typing');

      controller.text = 'mo the office';
      async.elapse(const Duration(milliseconds: 900));
      expect(returned, 0);
      async.elapse(const Duration(milliseconds: 200));
      expect(returned, 1);
      expect(watcher.isWatching, isFalse);
    });
  });

  test('stopping cancels a pending return', () {
    fakeAsync((async) {
      final controller = TextEditingController();
      var returned = 0;
      final watcher = DictationAutoReturn(controller: controller, onSpoken: () => returned++)..start();
      controller.text = 'breaking bad';
      watcher.stop();
      async.elapse(const Duration(seconds: 2));
      expect(returned, 0);
    });
  });
}
