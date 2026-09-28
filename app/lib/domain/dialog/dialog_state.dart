/// Конечный автомат диалога (ТЗ, раздел 5):
/// idle -> listening -> processing -> awaitingConfirmation / awaitingChoice -> executing -> idle
enum DialogState {
  idle,
  listening,
  processing,
  awaitingConfirmation,
  awaitingChoice,
  executing;

  /// Допустимые переходы. Всё остальное — ошибка в логике, а не в речи.
  static const Map<DialogState, Set<DialogState>> _allowed = {
    // idle -> processing: путь фразы активации, где отдельного шага
    // «нажал кнопку» нет (ТЗ, FR-1, этап 5).
    DialogState.idle: {DialogState.listening, DialogState.processing},
    DialogState.listening: {DialogState.processing, DialogState.idle},
    DialogState.processing: {
      DialogState.executing,
      DialogState.awaitingConfirmation,
      DialogState.awaitingChoice,
      DialogState.idle,
    },
    // Навык не выполнил команду, а задал вопрос, — возврат из executing.
    DialogState.executing: {
      DialogState.idle,
      DialogState.awaitingConfirmation,
      DialogState.awaitingChoice,
    },
    DialogState.awaitingConfirmation: {
      DialogState.listening,
      DialogState.processing,
      DialogState.idle,
    },
    DialogState.awaitingChoice: {
      DialogState.listening,
      DialogState.processing,
      DialogState.idle,
    },
  };

  bool canGoTo(DialogState next) => _allowed[this]!.contains(next);

  /// В этих состояниях ассистент ждёт ответа на свой вопрос.
  bool get isAwaiting =>
      this == DialogState.awaitingConfirmation ||
      this == DialogState.awaitingChoice;
}
