/// Plain Dart data layer — the DSL never touches this.
/// Repositories, services and DTOs live here, all testable and injectable.
class User {
  const User(this.name, this.photo);

  final String name;
  final String? photo;
}

class UserRepository {
  /// Stands in for a network call.
  Future<User> currentUser() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return const User('Ada Lovelace', null);
  }
}
