import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../state/session.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.session});

  final Session session;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _imagePicker = ImagePicker();
  final _displayName = TextEditingController();
  final _photoUrl = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = true;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _deletingAvatar = false;
  String? _error;
  Map<String, dynamic>? _profile;
  Uint8List? _selectedAvatarBytes;
  String? _selectedAvatarName;
  String? _selectedAvatarContentType;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _displayName.dispose();
    _photoUrl.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _clearSelectedAvatar() {
    _selectedAvatarBytes = null;
    _selectedAvatarName = null;
    _selectedAvatarContentType = null;
  }

  Future<void> _hydrate() async {
    setState(() {
      _loading = true;
      _error = null;
      _clearSelectedAvatar();
    });
    try {
      await widget.session.refreshProfile();
      if (!mounted) return;
      _profile = widget.session.bootstrap;
      _displayName.text = widget.session.displayName ?? '';
      _photoUrl.text = widget.session.photoUrl ?? '';
      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pickAvatarFile() async {
    try {
      final file = await _imagePicker.pickImage(source: ImageSource.gallery);
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() => _error = 'The selected image was empty.');
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedAvatarBytes = bytes;
        _selectedAvatarName = file.name;
        _selectedAvatarContentType = _contentTypeForFileName(file.name);
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '$error');
    }
  }

  Future<void> _saveProfile() async {
    final name = _displayName.text.trim();
    final photoUrl = _photoUrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Display name cannot be empty.');
      return;
    }
    setState(() {
      _savingProfile = true;
      _error = null;
    });
    try {
      await widget.session.updateDisplayName(name);
      if (_selectedAvatarBytes != null && _selectedAvatarContentType != null) {
        await widget.session.uploadAvatar(
          _selectedAvatarBytes!,
          contentType: _selectedAvatarContentType!,
        );
      }
      await widget.session.updatePhotoUrl(photoUrl.isEmpty ? null : photoUrl);
      if (_selectedAvatarBytes != null && mounted) {
        setState(_clearSelectedAvatar);
      }
      await widget.session.refreshProfile();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() {
      _deletingAvatar = true;
      _error = null;
    });
    try {
      await widget.session.deleteAvatar();
      await widget.session.refreshProfile();
      if (mounted) {
        setState(_clearSelectedAvatar);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar removed')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _deletingAvatar = false);
      }
    }
  }

  Future<void> _changePassword() async {
    final password = _newPassword.text;
    final confirm = _confirmPassword.text;
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    setState(() {
      _savingPassword = true;
      _error = null;
    });
    try {
      await widget.session.changePassword(password);
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) {
        setState(() => _savingPassword = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    final trimmedName = _displayName.text.trim();
    final initials = trimmedName.isEmpty ? '?' : trimmedName.substring(0, 1).toUpperCase();
    final avatarBytes = _selectedAvatarBytes ?? widget.session.avatarBytes;
    final photoUrl = _selectedAvatarBytes == null ? widget.session.photoUrl : null;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Profile',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Update your in-app identity, avatar, and password.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _MessageCard(message: _error!, isError: true),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final left = _ProfileCard(
              title: 'Identity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: _AvatarPreview(
                      bytes: avatarBytes,
                      photoUrl: photoUrl,
                      initials: initials,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _displayName,
                    decoration: const InputDecoration(
                      labelText: 'Display name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _savingProfile ? null : _pickAvatarFile,
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('Upload image file'),
                        ),
                      ),
                      if (_selectedAvatarBytes != null) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _savingProfile ? null : () => setState(_clearSelectedAvatar),
                          icon: const Icon(Icons.clear_rounded),
                          label: const Text('Clear selected file'),
                        ),
                      ],
                      if (widget.session.avatarBytes != null) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _savingProfile || _deletingAvatar ? null : _deleteAvatar,
                          icon: _deletingAvatar
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.delete_outline_rounded),
                          label: const Text('Remove avatar'),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedAvatarName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Selected file: $_selectedAvatarName',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _photoUrl,
                    decoration: const InputDecoration(
                      labelText: 'Avatar URL fallback',
                      hintText: 'Optional legacy URL',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Use a URL only if you do not want to upload a file.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _savingProfile ? null : _saveProfile,
                    icon: _savingProfile
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text('Save profile'),
                  ),
                ],
              ),
            );

            final right = Column(
              children: [
                _ProfileCard(
                  title: 'Account details',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _InfoRow(label: 'Email', value: widget.session.email ?? '-'),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'User ID', value: widget.session.userId ?? '-'),
                      const SizedBox(height: 10),
                      _InfoRow(label: 'Tenant', value: widget.session.tenantId ?? '-'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ProfileCard(
                  title: 'Change password',
                  child: Column(
                    children: [
                      TextField(
                        controller: _newPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmPassword,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _savingPassword ? null : _changePassword,
                          icon: _savingPassword
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.password_rounded),
                          label: const Text('Update password'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _ProfileCard(
                  title: 'Live profile',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.session.displayName ?? 'Unnamed operator'),
                      const SizedBox(height: 6),
                      Text(
                        _profile == null ? 'Profile not loaded yet.' : 'Profile is synced from DartStream.',
                        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );

            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: left),
                  const SizedBox(width: 16),
                  Expanded(flex: 5, child: right),
                ],
              );
            }
            return Column(
              children: [
                left,
                const SizedBox(height: 16),
                right,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF4C1D1D) : const Color(0xFF0F5132),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message),
    );
  }
}

class _AvatarPreview extends StatelessWidget {
  const _AvatarPreview({
    required this.bytes,
    required this.photoUrl,
    required this.initials,
  });

  final Uint8List? bytes;
  final String? photoUrl;
  final String initials;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = bytes != null && bytes!.isNotEmpty
        ? Image.memory(bytes!, fit: BoxFit.cover, width: 84, height: 84)
        : photoUrl != null && photoUrl!.isNotEmpty
            ? Image.network(
                photoUrl!,
                fit: BoxFit.cover,
                width: 84,
                height: 84,
                errorBuilder: (context, error, stackTrace) {
                  return _AvatarFallback(initials: initials);
                },
              )
            : _AvatarFallback(initials: initials);

    return Container(
      width: 84,
      height: 84,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

String _contentTypeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.gif')) return 'image/gif';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.bmp')) return 'image/bmp';
  if (lower.endsWith('.heic')) return 'image/heic';
  if (lower.endsWith('.heif')) return 'image/heif';
  if (lower.endsWith('.avif')) return 'image/avif';
  return 'image/jpeg';
}
