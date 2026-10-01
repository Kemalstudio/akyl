import 'package:akyl/domain/dialog/wake_phrase.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('команда после имени', () {
    expect(wakeCommand('Макс привет'), 'привет');
    expect(wakeCommand('макс, позвони маме'), 'позвони маме');
    expect(wakeCommand('Эй Макс! какое сегодня число'), 'какое сегодня число');
    expect(wakeCommand('Max позвони папе'), 'позвони папе');
    expect(wakeCommand('ну Макс позвони маме'), 'позвони маме');
  });

  test('одно имя — команду надо дослушать', () {
    expect(wakeCommand('Макс'), '');
    expect(wakeCommand('макс.'), '');
  });

  test('без обращения — пропуск', () {
    expect(wakeCommand('позвони маме'), isNull);
    expect(wakeCommand('Максим позвони'), isNull);
    expect(wakeCommand('позвони Максу'), isNull);
    expect(wakeCommand(''), isNull);
  });
}
