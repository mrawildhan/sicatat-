import 'sicatat_types.dart';

enum UserRole { crew, foreman, supervisorCop, supervisorSmg, foremanLv, admin }

class AppUser {
  const AppUser({
    required this.id,
    required this.nik,
    required this.name,
    required this.role,
    required this.isActive,
    this.teamId,
    this.siteId,
    this.siteName,
    this.phone,
  });

  final String id;
  final String nik;
  final String name;
  final UserRole role;
  final bool isActive;
  final String? teamId;
  final String? siteId;
  final String? siteName;
  final String? phone;

  factory AppUser.fromJson(JsonMap json) {
    final Object? rawSite = json['site'];
    final JsonMap? site = rawSite == null
        ? null
        : requireJsonMap(rawSite, source: 'user site');
    return AppUser(
      id: json.requiredString('id'),
      nik: json.requiredString('nik'),
      name: json.requiredString('name'),
      role: UserRoleX.fromStorage(json.requiredString('role')),
      isActive: json.requiredBool('is_active'),
      teamId: json.optionalString('team_id'),
      siteId: json.optionalString('site_id'),
      siteName: site?.optionalString('name'),
      phone: json.optionalString('phone'),
    );
  }
}

extension UserRoleX on UserRole {
  static UserRole fromStorage(String value) => switch (value) {
    'crew' => UserRole.crew,
    'foreman' => UserRole.foreman,
    // Legacy accounts remain usable while production data is migrated.
    'supervisor' || 'supervisor_smg' => UserRole.supervisorSmg,
    'supervisor_cop' => UserRole.supervisorCop,
    'foreman_lv' => UserRole.foremanLv,
    'admin' => UserRole.admin,
    _ => throw FormatException('Unknown user role: $value'),
  };

  String get storageValue => switch (this) {
    UserRole.crew => 'crew',
    UserRole.foreman => 'foreman',
    UserRole.supervisorCop => 'supervisor_cop',
    UserRole.supervisorSmg => 'supervisor_smg',
    UserRole.foremanLv => 'foreman_lv',
    UserRole.admin => 'admin',
  };

  String get label => switch (this) {
    UserRole.crew => 'Crew',
    UserRole.foreman => 'Foreman',
    UserRole.supervisorCop => 'Supervisor COP',
    UserRole.supervisorSmg => 'Supervisor SMG',
    UserRole.foremanLv => 'Foreman LV',
    UserRole.admin => 'Admin',
  };

  bool get isGlobalTemperatureManager =>
      this == UserRole.admin || this == UserRole.supervisorSmg;

  bool get canCreateTemperatureSheet =>
      this == UserRole.crew || isGlobalTemperatureManager;

  bool get canReviewTemperature =>
      this == UserRole.foreman ||
      this == UserRole.supervisorCop ||
      isGlobalTemperatureManager;

  bool get isTeamScopedTemperature => this == UserRole.foreman;

  bool get isSiteScopedTemperature => this == UserRole.supervisorCop;

  bool get canUseReminders =>
      this == UserRole.admin ||
      this == UserRole.supervisorSmg ||
      this == UserRole.foremanLv;

  bool get canManageUsers => this == UserRole.admin;

  bool get canManageMasterData =>
      this == UserRole.admin || this == UserRole.supervisorSmg;
}
