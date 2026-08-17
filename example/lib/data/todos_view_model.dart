import 'package:flx/flx.dart';

class Todo {
  const Todo(this.title, {this.done = false});

  final String title;
  final bool done;

  Todo toggled() => Todo(title, done: !done);
}

/// State that outlives a single build, kept out of the widget entirely.
///
/// The screen reads it with `useViewModel<TodosViewModel>()` and rebuilds
/// whenever [notify] fires — so the UI stays a pure function of this object.
class TodosViewModel extends ViewModel {
  final _todos = <Todo>[
    const Todo('Learn flx'),
    const Todo('Port the transpiler to Dart', done: true),
    const Todo('Ship the flagship app'),
  ];

  List<Todo> get todos => List.unmodifiable(_todos);

  bool get isEmpty => _todos.isEmpty;

  int get remaining => _todos.where((t) => !t.done).length;

  void add(String title) {
    if (title.trim().isEmpty) return;
    _todos.add(Todo(title.trim()));
    notify();
  }

  void toggle(int index) {
    _todos[index] = _todos[index].toggled();
    notify();
  }

  void clearCompleted() {
    _todos.removeWhere((t) => t.done);
    notify();
  }
}
