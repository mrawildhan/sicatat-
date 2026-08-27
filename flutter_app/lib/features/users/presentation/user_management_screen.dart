import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/sicatat_types.dart';

String _roleLabel(String role) => switch (role) {
  'crew' => 'Crew',
  'foreman' => 'Foreman',
  'supervisor_cop' => 'Supervisor COP',
  'supervisor_smg' || 'supervisor' => 'Supervisor SMG',
  'foreman_lv' => 'Foreman LV',
  'admin' => 'Admin',
  _ => role,
};

class _TeamOption {
  const _TeamOption({required this.id, required this.name});
  final String id;
  final String name;
  factory _TeamOption.fromJson(JsonMap json) => _TeamOption(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class _SiteOption {
  const _SiteOption({required this.id, required this.name});
  final String id;
  final String name;
  factory _SiteOption.fromJson(JsonMap json) => _SiteOption(
    id: json.requiredString('id'),
    name: json.requiredString('name'),
  );
}

class _ManagedUser {
  const _ManagedUser({
    required this.id,
    required this.nik,
    required this.name,
    required this.role,
    required this.isActive,
    this.teamId,
    this.teamName,
    this.siteId,
    this.siteName,
    this.phone,
  });
  final String id;
  final String nik;
  final String name;
  final String role;
  final bool isActive;
  final String? teamId;
  final String? teamName;
  final String? siteId;
  final String? siteName;
  final String? phone;
  factory _ManagedUser.fromJson(JsonMap json) {
    final Object? rawTeam = json['team'];
    final JsonMap? team = rawTeam == null
        ? null
        : requireJsonMap(rawTeam, source: 'user team');
    final Object? rawSite = json['site'];
    final JsonMap? site = rawSite == null
        ? null
        : requireJsonMap(rawSite, source: 'user site');
    return _ManagedUser(
      id: json.requiredString('id'),
      nik: json.requiredString('nik'),
      name: json.requiredString('name'),
      role: json.requiredString('role'),
      isActive: json.requiredBool('is_active'),
      teamId: json.optionalString('team_id'),
      teamName: team?.optionalString('name'),
      siteId: json.optionalString('site_id'),
      siteName: site?.optionalString('name'),
      phone: json.optionalString('phone'),
    );
  }
}

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});
  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final TextEditingController _nikController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  static const List<String> _roles = <String>[
    'crew',
    'foreman',
    'supervisor_cop',
    'supervisor_smg',
    'foreman_lv',
    'admin',
  ];
  List<_TeamOption> _teams = const <_TeamOption>[];
  List<_SiteOption> _sites = const <_SiteOption>[];
  List<_ManagedUser> _users = const <_ManagedUser>[];
  String? _teamId;
  String? _siteId;
  String _role = 'crew';
  bool _isActive = true;
  bool _loading = true;
  bool _saving = false;
  bool _creating = false;
  _ManagedUser? _editing;

  bool get _isFormOpen => _creating || _editing != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nikController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final List<Object> responses = await Future.wait<Object>(<Future<Object>>[
        Supabase.instance.client
            .from('team')
            .select('id,name')
            .eq('is_active', true)
            .order('code'),
        Supabase.instance.client
            .from('site')
            .select('id,name')
            .eq('is_active', true)
            .order('name'),
        Supabase.instance.client
            .from('app_user')
            .select(
              'id,nik,name,role,team_id,site_id,phone,is_active,team:team_id(name),site:site_id(name)',
            )
            .order('name'),
      ]);
      final Object teamResponse = responses[0];
      final Object siteResponse = responses[1];
      final Object userResponse = responses[2];
      if (teamResponse is! List ||
          siteResponse is! List ||
          userResponse is! List) {
        throw const FormatException(
          'The server returned an invalid user list.',
        );
      }
      final List<_TeamOption> teams = teamResponse
          .map((Object? row) => _TeamOption.fromJson(requireJsonMap(row)))
          .toList(growable: false);
      final List<_SiteOption> sites = siteResponse
          .map((Object? row) => _SiteOption.fromJson(requireJsonMap(row)))
          .toList(growable: false);
      final List<_ManagedUser> users = userResponse
          .map((Object? row) => _ManagedUser.fromJson(requireJsonMap(row)))
          .toList(growable: false);
      if (mounted) {
        setState(() {
          _teams = teams;
          _sites = sites;
          _users = users;
        });
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to load users: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _roleNeedsTeam => _role == 'crew' || _role == 'foreman';
  bool get _roleNeedsSite => _role == 'supervisor_cop';
  void _openCreate() {
    _creating = true;
    _editing = null;
    _nikController.clear();
    _nameController.clear();
    _phoneController.clear();
    _pinController.clear();
    _role = 'crew';
    _teamId = _teams.isEmpty ? null : _teams.first.id;
    _siteId = _sites.isEmpty ? null : _sites.first.id;
    _isActive = true;
    setState(() {});
  }

  void _openEdit(_ManagedUser user) {
    _creating = false;
    _editing = user;
    _nikController.text = user.nik;
    _nameController.text = user.name;
    _phoneController.text = user.phone ?? '';
    _pinController.clear();
    _role = user.role;
    _teamId = user.teamId;
    _siteId = user.siteId;
    _isActive = user.isActive;
    setState(() {});
  }

  void _closeForm() => setState(() {
    _creating = false;
    _editing = null;
  });
  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final String nik = _nikController.text.trim();
    final String name = _nameController.text.trim();
    final String phone = _phoneController.text.trim();
    if (nik.isEmpty || name.isEmpty) {
      _message('Crew ID and name are required.');
      return;
    }
    if (_roleNeedsTeam && _teamId == null) {
      _message('A team is required for crew and foreman users.');
      return;
    }
    if (_roleNeedsSite && _siteId == null) {
      _message('A site is required for Supervisor COP users.');
      return;
    }
    if (_editing == null && _pinController.text.length < 6) {
      _message('PIN must contain at least 6 characters.');
      return;
    }
    setState(() => _saving = true);
    try {
      if (_editing == null) {
        final FunctionResponse response = await Supabase
            .instance
            .client
            .functions
            .invoke(
              'create-crew-user',
              body: <String, Object?>{
                'nik': nik,
                'name': name,
                'role': _role,
                'team_id': _roleNeedsTeam ? _teamId : null,
                'site_id': _roleNeedsSite ? _siteId : null,
                'phone': phone.isEmpty ? null : phone,
                'pin': _pinController.text,
              },
            );
        final JsonMap data = requireJsonMap(
          response.data,
          source: 'create user response',
        );
        if (data['ok'] != true) {
          throw FormatException(
            data.optionalString('error') ?? 'The server rejected the user.',
          );
        }
        _message(
          'User created. They can sign in with Crew ID $nik and their PIN.',
        );
      } else {
        await Supabase.instance.client
            .from('app_user')
            .update(<String, Object?>{
              'name': name,
              'role': _role,
              'team_id': _roleNeedsTeam ? _teamId : null,
              'site_id': _roleNeedsSite ? _siteId : null,
              'phone': phone.isEmpty ? null : phone,
              'is_active': _isActive,
            })
            .eq('id', _editing!.id);
        _message('User updated.');
      }
      if (mounted) {
        _closeForm();
        await _load();
      }
    } on Object catch (error) {
      if (mounted) _message('Unable to save user: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_isFormOpen) {
        _closeForm();
      } else {
        context.go('/admin');
      }
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: !_isFormOpen
              ? 'Back to administration'
              : 'Back to user list',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: !_isFormOpen ? () => context.go('/admin') : _closeForm,
        ),
        title: const Text('User management'),
      ),
      floatingActionButton: !_isFormOpen
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _openCreate,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Add user'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: <Widget>[
                if (_isFormOpen || _users.isEmpty) _form(),
                if (!_isFormOpen && _users.isNotEmpty) ...<Widget>[
                  const Text(
                    'Tap a user to edit their role, team, phone number, or active status.',
                  ),
                  const SizedBox(height: 14),
                  ..._users.map(_userTile),
                ],
              ],
            ),
    ),
  );

  Widget _userTile(_ManagedUser user) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        onTap: () => _openEdit(user),
        leading: CircleAvatar(
          child: Text(user.name.substring(0, 1).toUpperCase()),
        ),
        title: Text(
          user.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${user.nik} · ${_roleLabel(user.role)}${user.teamName == null ? '' : ' · ${user.teamName}'}${user.siteName == null ? '' : ' · ${user.siteName}'}',
        ),
        trailing: Chip(label: Text(user.isActive ? 'Active' : 'Inactive')),
      ),
    ),
  );

  Widget _form() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Text(
        _editing == null ? 'Create user account' : 'Edit user account',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(
        _editing == null
            ? 'The user can sign in immediately using their Crew ID and PIN.'
            : 'Crew ID cannot be changed after the account is created.',
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _nikController,
        enabled: _editing == null,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Crew ID / NIK'),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _nameController,
        decoration: const InputDecoration(labelText: 'Full name'),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: ValueKey<String>('role-${_editing?.id ?? 'new'}'),
        initialValue: _role,
        items: _roles
            .map(
              (String role) => DropdownMenuItem<String>(
                value: role,
                child: Text(_roleLabel(role)),
              ),
            )
            .toList(growable: false),
        onChanged: (String? value) => setState(() => _role = value ?? 'crew'),
        decoration: const InputDecoration(labelText: 'Role'),
      ),
      if (_roleNeedsTeam) ...<Widget>[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey<String>('team-${_editing?.id ?? 'new'}'),
          initialValue: _teamId,
          items: _teams
              .map(
                (team) => DropdownMenuItem<String>(
                  value: team.id,
                  child: Text(team.name),
                ),
              )
              .toList(growable: false),
          onChanged: (String? value) => setState(() => _teamId = value),
          decoration: const InputDecoration(labelText: 'Team'),
        ),
      ],
      if (_roleNeedsSite) ...<Widget>[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey<String>('site-${_editing?.id ?? 'new'}'),
          initialValue: _siteId,
          items: _sites
              .map(
                (site) => DropdownMenuItem<String>(
                  value: site.id,
                  child: Text(site.name),
                ),
              )
              .toList(growable: false),
          onChanged: (String? value) => setState(() => _siteId = value),
          decoration: const InputDecoration(labelText: 'Site scope'),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Phone number (optional)'),
      ),
      if (_editing == null) ...<Widget>[
        const SizedBox(height: 12),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'PIN (at least 6 characters)',
          ),
        ),
      ],
      if (_editing != null)
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _isActive,
          onChanged: (bool value) => setState(() => _isActive = value),
          title: const Text('Account active'),
        ),
      const SizedBox(height: 18),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: const Icon(Icons.save_rounded),
        label: Text(_saving ? 'Saving...' : 'Save user'),
      ),
      TextButton(
        onPressed: _saving ? null : _closeForm,
        child: const Text('Cancel'),
      ),
    ],
  );
}
