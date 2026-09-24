import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/app_preferences.dart';
import '../../services/messenger_coordinator.dart';
import '../../localization/app_locale.dart';
import 'app_avatar.dart';
import 'glass_dialog.dart';
import '../../theme/theme_provider.dart';

/// Hộp thoại chọn và tùy chỉnh Ảnh đại diện (Avatar Picker Dialog cho cả Cá nhân & Nhóm)
class AvatarPickerDialog extends StatefulWidget {
  final String? targetGroupId;
  final String? groupName;
  final Color? initialColor;
  final String? initialPreset;
  final String? initialCustomPath;
  final String? initialCustomBase64;
  final String? initialType;
  final String? initialGroupName;
  final bool canRenameGroup;

  const AvatarPickerDialog({
    super.key,
    this.targetGroupId,
    this.groupName,
    this.initialColor,
    this.initialPreset,
    this.initialCustomPath,
    this.initialCustomBase64,
    this.initialType,
    this.initialGroupName,
    this.canRenameGroup = false,
  });

  static Future<void> show(
    BuildContext context, {
    String? targetGroupId,
    String? groupName,
    Color? initialColor,
    String? initialPreset,
    String? initialCustomPath,
    String? initialCustomBase64,
    String? initialType,
    String? initialGroupName,
    bool canRenameGroup = false,
  }) {
    return showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => AvatarPickerDialog(
        targetGroupId: targetGroupId,
        groupName: groupName,
        initialColor: initialColor,
        initialPreset: initialPreset,
        initialCustomPath: initialCustomPath,
        initialCustomBase64: initialCustomBase64,
        initialType: initialType,
        initialGroupName: initialGroupName,
        canRenameGroup: canRenameGroup,
      ),
    );
  }

  @override
  State<AvatarPickerDialog> createState() => _AvatarPickerDialogState();
}

class _AvatarPickerDialogState extends State<AvatarPickerDialog> {
  late String _selectedType;
  late String _selectedPreset;
  late String _selectedCustomPath;
  late String _selectedCustomBase64;
  late Color _selectedColor;
  late final TextEditingController _groupNameController;

  @override
  void initState() {
    super.initState();
    _groupNameController = TextEditingController(
      text: widget.initialGroupName ?? widget.groupName ?? '',
    );
    _selectedCustomBase64 = widget.initialCustomBase64 ?? '';
    if (widget.targetGroupId != null) {
      final hasImage =
          (widget.initialCustomPath != null &&
              widget.initialCustomPath!.isNotEmpty) ||
          _selectedCustomBase64.isNotEmpty;
      _selectedType =
          widget.initialType ??
          (hasImage
              ? 'custom'
              : (widget.initialPreset != null &&
                        widget.initialPreset!.isNotEmpty
                    ? 'preset'
                    : 'preset'));
      _selectedPreset = widget.initialPreset ?? 'game';
      _selectedCustomPath = widget.initialCustomPath ?? '';
      _selectedColor = widget.initialColor ?? const Color(0xFF6366F1);
    } else {
      final prefs = AppPreferences();
      _selectedType = widget.initialType ?? prefs.userAvatarType;
      _selectedPreset = widget.initialPreset ?? prefs.userAvatarPreset;
      _selectedCustomPath =
          widget.initialCustomPath ?? prefs.userAvatarCustomPath;
      if (_selectedCustomBase64.isEmpty) {
        _selectedCustomBase64 = prefs.userAvatarBase64;
      }

      final colorHex = prefs.userAvatarColor.replaceFirst('#', '');
      try {
        final val = int.parse(
          colorHex.length == 6 ? 'FF$colorHex' : colorHex,
          radix: 16,
        );
        _selectedColor = widget.initialColor ?? Color(val);
      } catch (_) {
        _selectedColor = widget.initialColor ?? const Color(0xFF3B82F6);
      }
    }
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _pickImageFromPc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (mounted && result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        setState(() {
          _selectedCustomPath = path;
          _selectedType = 'custom';
        });
      }
    } catch (e) {
      debugPrint('[AvatarPicker] Error picking image: $e');
    }
  }

  Future<void> _save() async {
    final coordinator = context.read<MessengerCoordinator>();
    if (widget.targetGroupId != null) {
      if (!coordinator.isGroupAdmin(widget.targetGroupId!)) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final renamed = _groupNameController.text.trim();
      if (renamed.isNotEmpty &&
          renamed != (widget.initialGroupName ?? widget.groupName ?? '')) {
        coordinator.renameGroup(widget.targetGroupId!, renamed);
      }
      final keepRemoteImage =
          _selectedType == 'custom' &&
          _selectedCustomPath.isEmpty &&
          _selectedCustomBase64.isNotEmpty;
      await coordinator.updateGroupAvatar(
        widget.targetGroupId!,
        color: _selectedColor,
        preset: _selectedType == 'preset' ? _selectedPreset : null,
        customPath: _selectedType == 'custom' && _selectedCustomPath.isNotEmpty
            ? _selectedCustomPath
            : null,
        customBase64: keepRemoteImage ? _selectedCustomBase64 : null,
      );
    } else {
      await coordinator.updateUserAvatar(
        type: _selectedType,
        preset: _selectedPreset,
        customPath: _selectedCustomPath,
        color: _selectedColor,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final isDark = ThemeProvider.of(context).isDark;
    final ink = isDark ? Colors.white : Colors.black87;
    final canEdit =
        widget.targetGroupId == null ||
        (context.watch<MessengerCoordinator?>()?.isGroupAdmin(
              widget.targetGroupId!,
            ) ??
            false);

    return GlassDialog(
      title: widget.targetGroupId != null
          ? lang.tr('groupAvatarTitle')
          : lang.tr('avatarPickerTitle'),
      icon: Icons.account_circle_rounded,
      width: 480,
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            lang.tr('cancel'),
            style: TextStyle(color: ink.withValues(alpha: 0.7)),
          ),
        ),
        ElevatedButton(
          onPressed: canEdit ? _save : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedColor,
            foregroundColor: _selectedColor.computeLuminance() > 0.4
                ? Colors.black87
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(lang.tr('confirm')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Live Avatar Preview
          Center(
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _selectedColor.withValues(alpha: 0.6),
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _selectedColor.withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ClipOval(
                child: SizedBox(width: 80, height: 80, child: _buildPreview()),
              ),
            ),
          ),
          if (widget.targetGroupId != null) ...[
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lang.tr('groupNameLabel'),
                style: TextStyle(
                  color: ink.withValues(alpha: 0.8),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _groupNameController,
              enabled: canEdit,
              maxLength: 256,
              decoration: InputDecoration(
                hintText: lang.tr('groupNameHint'),
                counterText: '',
                filled: true,
                fillColor: ink.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (!canEdit)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  lang.tr('onlyAdminCanRename'),
                  style: TextStyle(
                    color: ink.withValues(alpha: 0.55),
                    fontSize: 11,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 16),

          // 2. Button chọn ảnh từ máy tính
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: !canEdit ? null : _pickImageFromPc,
              style: OutlinedButton.styleFrom(
                foregroundColor: ink,
                side: BorderSide(color: ink.withValues(alpha: 0.2)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              label: Text(lang.tr('chooseFromPc')),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Chọn biểu tượng có sẵn (Preset Icons)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              lang.tr('presetIcons'),
              style: TextStyle(
                color: ink.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            height: 120,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ink.withValues(alpha: 0.08)),
            ),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: AvatarPresets.icons.length,
              itemBuilder: (context, index) {
                final key = AvatarPresets.icons.keys.elementAt(index);
                final icon = AvatarPresets.icons.values.elementAt(index);
                final isSelected =
                    _selectedType == 'preset' && _selectedPreset == key;

                return InkWell(
                  onTap: !canEdit
                      ? null
                      : () {
                          setState(() {
                            _selectedType = 'preset';
                            _selectedPreset = key;
                          });
                        },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _selectedColor.withValues(alpha: 0.3)
                          : ink.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? _selectedColor
                            : ink.withValues(alpha: 0.1),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Icon(icon, size: 20, color: ink),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // 4. Chọn màu nền (Avatar Color Palette)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              lang.tr('avatarColor'),
              style: TextStyle(
                color: ink.withValues(alpha: 0.8),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AvatarPresets.paletteColors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final color = AvatarPresets.paletteColors[index];
                final isSelected =
                    _selectedColor.toARGB32() == color.toARGB32();

                return InkWell(
                  onTap: !canEdit
                      ? null
                      : () {
                          setState(() {
                            _selectedColor = color;
                          });
                        },
                  borderRadius: BorderRadius.circular(18),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: Colors.white,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_selectedType == 'custom' &&
        _selectedCustomPath.isNotEmpty &&
        File(_selectedCustomPath).existsSync()) {
      return Image.file(
        File(_selectedCustomPath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            _buildFallbackIcon(AvatarPresets.getIcon('robot')),
      );
    }

    if (_selectedType == 'custom' && _selectedCustomBase64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(_selectedCustomBase64),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              _buildFallbackIcon(AvatarPresets.getIcon('robot')),
        );
      } catch (_) {
        return _buildFallbackIcon(AvatarPresets.getIcon('robot'));
      }
    }

    if (_selectedType == 'preset') {
      return _buildFallbackIcon(AvatarPresets.getIcon(_selectedPreset));
    }

    if (widget.targetGroupId != null) {
      final gName = (widget.groupName ?? '').trim();
      final initials = gName.isNotEmpty
          ? gName.substring(0, 1).toUpperCase()
          : 'G';
      return Container(
        color: _selectedColor.withValues(alpha: 0.2),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: _selectedColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    final name =
        AppPreferences().localNickname ??
        Platform.environment['USERNAME'] ??
        'User';
    final initials = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';
    return Container(
      color: _selectedColor.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: _selectedColor,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(IconData icon) {
    return Container(
      color: _selectedColor.withValues(alpha: 0.2),
      child: Center(child: Icon(icon, color: _selectedColor, size: 42)),
    );
  }
}
