import 'sicatat_types.dart';

enum UserRole { crew, foreman, supervisor, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.nik,
    required this.name,
    required this.role,
    required this.isActive,
    this.teamId,
    this.phone,
  });

  final String id;
  final String nik;
  final String name;
  final UserRole role;
  final bool isActive;
  final String? teamId;
  final String? phone;

  factory AppUser.fromJson(JsonMap json) {
    return AppUser(
      id: json.requiredString('id'),
      nik: json.requiredString('nik'),
      name: json.requiredString('name'),
      role: UserRoleX.fromStorage(json.requiredString('role')),
      isActive: json.requiredBool('is_active'),
      teamId: json.optionalString('team_id'),
      phone: json.optionalString('phone'),
    );
  }
}

extension UserRoleX on UserRole {
  static UserRole fromStorage(String value) => switch (value) {
    'crew' => UserRole.crew,
    'foreman' => UserRole.foreman,
    'supervisor' => UserRole.supervisor,
    'admin' => UserRole.admin,
    _ => throw FormatException('Unknown user role: $value'),
  };
}
