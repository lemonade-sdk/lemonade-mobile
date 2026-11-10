import 'package:lemonade_nexus_sdk/lemonade_nexus_sdk.dart' show NetworkDevice;

/// The role an invite gives the device that joins with it. The permission
/// names of each role are the presets of lemond's invite dialog
/// (lemonade `src/cpp/server/nexus_manager.cpp`, `role_permissions`), so a
/// device invited from a phone and one invited from a computer get the same
/// access. The network stores and replicates the `svc:` names and the
/// receiving device enforces them; `read`, `write`, `add_child`,
/// `connect_private` and `admin` are tree permissions the network checks.
enum MeshRole {
  user('User', 'Uses the inference servers of the network.'),
  moderator(
      'Moderator',
      'Uses the inference servers, manages models and jobs, and invites '
          'other devices.'),
  administrator(
      'Administrator',
      'Manages the network, its devices and their roles, and everything a '
          'moderator does.');

  final String label;
  final String description;
  const MeshRole(this.label, this.description);
}

/// Shown when this device may not invite: it holds no add_child on its
/// group, as a device invited as a user.
const String meshInviteNotAllowedMessage =
    'Only an administrator or a moderator of the network can invite devices. '
    'Ask one of them for an invite code, or for a role that allows it.';

/// lemond's route families, as `svc:<family>` permission names.
const List<String> kMeshServiceFamilies = [
  'inference',
  'mcp',
  'models_manage',
  'backends',
  'jobs',
  'internal',
  'system',
  'management',
];

/// The permission names an invite as [role] carries.
List<String> meshRolePermissions(MeshRole role) => switch (role) {
      MeshRole.user => const ['read', 'connect_private', 'svc:inference'],
      MeshRole.moderator => const [
          'read',
          'write',
          'add_child',
          'connect_private',
          'svc:inference',
          'svc:mcp',
          'svc:models_manage',
          'svc:jobs',
        ],
      MeshRole.administrator => [
          'read',
          'connect_private',
          'admin',
          for (final family in kMeshServiceFamilies) 'svc:$family',
        ],
    };

/// What this device holds on its own group of the network: whether it
/// administers the group and the permission names assigned to it there.
/// Decides which roles it can invite with. The network refuses an invite
/// from a device without `add_child` on the group, and an invite that
/// carries a name the inviter does not hold, unless the inviter administers
/// the group.
class MeshAccess {
  final String groupId;
  final bool admin;
  final List<String> permissions;

  const MeshAccess({required this.groupId, required this.admin, required this.permissions});

  bool get canInvite => admin || permissions.contains('add_child');

  /// The roles this device can invite with, the least first.
  List<MeshRole> get rolesOffered => admin
      ? MeshRole.values
      : canInvite
          ? const [MeshRole.user, MeshRole.moderator]
          : const [];

  /// The names an invite as [role] from this device carries: the whole
  /// preset for an administrator, else the names this device holds itself.
  List<String> invitePermissions(MeshRole role) {
    final preset = meshRolePermissions(role);
    if (admin) return preset;
    return [for (final name in preset) if (permissions.contains(name)) name];
  }

  /// This device's access from the network's device list ([devices], see
  /// [NetworkDevice]) and its memberships (`{node_id, role, permissions}`
  /// maps). Null when neither names this device's group.
  static MeshAccess? of(List<NetworkDevice>? devices, List<Map<String, dynamic>> memberships) {
    NetworkDevice? self;
    for (final d in devices ?? const <NetworkDevice>[]) {
      if (!d.isSelf) continue;
      if (self == null || (d.groupRole == 'home' && self.groupRole != 'home')) self = d;
    }
    var groupId = self?.groupId ?? '';
    if (groupId.isEmpty) {
      for (final m in memberships) {
        if (m['role'] == 'home') {
          groupId = m['node_id']?.toString() ?? '';
          break;
        }
      }
    }
    if (groupId.isEmpty) return null;
    final permissions = <String>[];
    for (final m in memberships) {
      if (m['node_id']?.toString() != groupId) continue;
      for (final p in m['permissions'] as List? ?? const []) {
        permissions.add(p.toString());
      }
    }
    return MeshAccess(
      groupId: groupId,
      admin: (self?.admin ?? false) || permissions.contains('admin'),
      permissions: permissions,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MeshAccess &&
      other.groupId == groupId &&
      other.admin == admin &&
      other.permissions.length == permissions.length &&
      other.permissions.every(permissions.contains);

  @override
  int get hashCode => Object.hash(groupId, admin, permissions.length);
}
