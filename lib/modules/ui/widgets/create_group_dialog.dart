import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../models/peer_model.dart';
import '../../services/messenger_coordinator.dart';
import '../../localization/app_locale.dart';
import '../../theme/theme_provider.dart';
import 'app_avatar.dart';
import 'glass_dialog.dart';

/// Hộp thoại tạo nhóm chat mới
class CreateGroupDialog extends StatefulWidget {
  final PeerModel? initialSelectedPeer;

  const CreateGroupDialog({super.key, this.initialSelectedPeer});

  static Future<void> show(
    BuildContext context, {
    PeerModel? initialSelectedPeer,
  }) {
    return showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) =>
          CreateGroupDialog(initialSelectedPeer: initialSelectedPeer),
    );
  }

  @override
  State<CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<CreateGroupDialog> {
  late final TextEditingController _nameController;
  final Set<String> _selectedMemberIds = {};
  String _memberSearchQuery = '';
  int _searchReset = 0;

  String _selectedAvatarType = 'preset';
  String _selectedAvatarPreset = 'game';
  String _selectedCustomPath = '';
  Color _selectedColor = const Color(0xFF6366F1);

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    if (widget.initialSelectedPeer != null) {
      _selectedMemberIds.add(widget.initialSelectedPeer!.id);
      _nameController.text = 'Nhóm ${widget.initialSelectedPeer!.displayName}';
    }
  }

  Future<void> _pickImageFromPc() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp', 'bmp'],
      );
      if (mounted && result != null && result.files.single.path != null) {
        setState(() {
          _selectedCustomPath = result.files.single.path!;
          _selectedAvatarType = 'custom';
        });
      }
    } catch (e) {
      debugPrint('[CreateGroup] Error picking image: $e');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.read<LanguageProvider>();
    final coordinator = context.read<MessengerCoordinator>();
    final ink = theme.isDark ? Colors.white : Colors.black87;

    final availablePeers = coordinator.peers
        .where((p) => !p.isGroup && !p.isAllUsers && !p.isAi)
        .toList();

    final filteredPeers = availablePeers.where((p) {
      if (_memberSearchQuery.isEmpty) return true;
      final q = _memberSearchQuery.toLowerCase();
      return p.name.toLowerCase().contains(q) ||
          p.ip.contains(q) ||
          (p.hostname?.toLowerCase().contains(q) ?? false);
    }).toList();

    return GlassDialog(
      title: lang.tr('createGroupTitle'),
      icon: Icons.groups_rounded,
      width: 440,
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
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            final name = _nameController.text.trim();
            if (name.isNotEmpty) {
              coordinator.createGroup(
                name,
                _selectedMemberIds.toList(),
                color: _selectedColor,
                avatarPreset: _selectedAvatarType == 'preset'
                    ? _selectedAvatarPreset
                    : null,
                customAvatarPath: _selectedAvatarType == 'custom'
                    ? _selectedCustomPath
                    : null,
              );
              Navigator.of(context).pop();
            }
          },
          child: Text(lang.tr('create')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Avatar xem trước + Nhập tên nhóm
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              InkWell(
                onTap: _pickImageFromPc,
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: _selectedColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _selectedColor.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _selectedColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child:
                          _selectedAvatarType == 'custom' &&
                              _selectedCustomPath.isNotEmpty &&
                              File(_selectedCustomPath).existsSync()
                          ? Image.file(
                              File(_selectedCustomPath),
                              fit: BoxFit.cover,
                            )
                          : Center(
                              child: Icon(
                                AvatarPresets.getIcon(_selectedAvatarPreset),
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: theme.colors.accentBlue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  autofocus: widget.initialSelectedPeer == null,
                  style: TextStyle(fontSize: 13, color: ink),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: lang.tr('groupNameHint'),
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.6),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. Chọn nhanh Icon Preset cho nhóm
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...AvatarPresets.icons.entries.take(8).map((entry) {
                  final isSelected =
                      _selectedAvatarType == 'preset' &&
                      _selectedAvatarPreset == entry.key;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedAvatarPreset = entry.key;
                          _selectedAvatarType = 'preset';
                        });
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _selectedColor.withValues(alpha: 0.25)
                              : ink.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? _selectedColor
                                : ink.withValues(alpha: 0.1),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          entry.value,
                          size: 16,
                          color: isSelected
                              ? _selectedColor
                              : ink.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  );
                }),
                InkWell(
                  onTap: _pickImageFromPc,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    height: 32,
                    decoration: BoxDecoration(
                      color: _selectedAvatarType == 'custom'
                          ? theme.colors.accentBlue.withValues(alpha: 0.2)
                          : ink.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _selectedAvatarType == 'custom'
                            ? theme.colors.accentBlue
                            : ink.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_rounded,
                          size: 14,
                          color: _selectedAvatarType == 'custom'
                              ? theme.colors.accentBlue
                              : ink.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          lang.tr('chooseFromPc'),
                          style: TextStyle(
                            fontSize: 11,
                            color: _selectedAvatarType == 'custom'
                                ? theme.colors.accentBlue
                                : ink.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 3. Chọn màu nền nhóm
          SizedBox(
            height: 24,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: AvatarPresets.paletteColors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final color = AvatarPresets.paletteColors[index];
                final isSelected =
                    _selectedColor.toARGB32() == color.toARGB32();
                return InkWell(
                  onTap: () => setState(() => _selectedColor = color),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                lang.tr('selectMembers'),
                style: TextStyle(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_selectedMemberIds.isNotEmpty)
                Text(
                  lang.tr('selectedMembers', [
                    _selectedMemberIds.length.toString(),
                  ]),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colors.accentBlue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            key: ValueKey(_searchReset),
            onChanged: (val) => setState(() => _memberSearchQuery = val),
            style: TextStyle(fontSize: 12, color: ink),
            decoration: InputDecoration(
              hintText: lang.tr('searchMembers'),
              hintStyle: TextStyle(
                fontSize: 11,
                color: ink.withValues(alpha: 0.6),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 16,
                color: ink.withValues(alpha: 0.6),
              ),
              suffixIcon: _memberSearchQuery.isEmpty
                  ? null
                  : IconButton(
                      tooltip: lang.tr('clear'),
                      icon: const Icon(Icons.clear_rounded, size: 16),
                      onPressed: () {
                        setState(() {
                          _memberSearchQuery = '';
                          _searchReset++;
                        });
                      },
                    ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              filled: true,
              fillColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: (theme.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.04,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: filteredPeers.isEmpty
                ? Center(
                    child: Text(
                      _memberSearchQuery.isNotEmpty
                          ? lang.tr('noPeersFound')
                          : lang.tr('noAvailableMembers'),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredPeers.length,
                    itemBuilder: (context, i) {
                      final p = filteredPeers[i];
                      final isChecked = _selectedMemberIds.contains(p.id);
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: isChecked,
                        secondary: AppAvatar(
                          peer: p,
                          size: 28,
                          showStatus: true,
                        ),
                        title: Text(
                          p.displayName,
                          style: TextStyle(fontSize: 12, color: ink),
                        ),
                        subtitle: Text(
                          p.ip,
                          style: TextStyle(
                            fontSize: 10,
                            color: ink.withValues(alpha: 0.7),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedMemberIds.add(p.id);
                            } else {
                              _selectedMemberIds.remove(p.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
