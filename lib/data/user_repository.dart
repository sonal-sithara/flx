/// Plain Dart data layer — the DSL never touches this.
/// Enterprise structure lives here: repositories, services, DTOs,
/// all testable and injectable.
class User {
  const User(this.name, this.photo);
  final String name;
  final String? photo;
}

class UserRepository {
  Future<User> currentUser() async {
    await Future.delayed(const Duration(seconds: 1));
    return const User('Ada Lovelace', null);
  }
}

/// Simple service locator for the prototype.
/// Swap for get_it / injectable / your own DI container later.
final api = UserRepository();
