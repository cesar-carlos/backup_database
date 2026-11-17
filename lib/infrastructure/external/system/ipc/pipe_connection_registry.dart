/// Tracks live connections by generation, never by a recyclable Win32 handle.
/// Reserve before spawning a worker so early port/exit messages cannot be lost.
class PipeConnectionRegistry<T> {
  final _live = <int, T>{};
  int _nextId = 0;

  int reserve(T connection) {
    final id = ++_nextId;
    _live[id] = connection;
    return id;
  }

  T? operator [](int id) => _live[id];
  T? finish(int id) => _live.remove(id);
  int get length => _live.length;
  List<T> get snapshot => _live.values.toList(growable: false);
}
