import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../localization/app_locale.dart';
import '../../models/message_model.dart';
import '../../models/peer_model.dart';
import '../../services/messenger_coordinator.dart';
import '../../services/sticker_service.dart';
import '../../theme/theme_provider.dart';
import 'app_avatar.dart';
import 'glass_dialog.dart';

/// Glassmorphic dialog for forwarding a text or file message to one or more
/// peers or groups, with an optional accompanying note.
class ForwardMessageDialog extends StatefulWidget {
  final MessageModel message;

  const ForwardMessageDialog({super.key, required this.message});

  static Future<void> show(BuildContext context, MessageModel message) {
    return showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => ForwardMessageDialog(message: message),
    );
  }

  @override
  State<ForwardMessageDialog> createState() => _ForwardMessageDialogState();
}

class _ForwardMessageDialogState extends State<ForwardMessageDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final Set<String> _selectedPeerIds = <String>{};
  String _searchQuery = '';
  bool _isSending = false;

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<PeerModel> _buildAvailableTargets(MessengerCoordinator coordinator) {
    final targets = <PeerModel>[];
    final seenIds = <String>{};

    for (final group in coordinator.groups) {
      final groupPeer = coordinator.getPeerForGroup(group);
      if (seenIds.add(groupPeer.id)) {
        targets.add(groupPeer);
      }
    }

    for (final peer in coordinator.peers) {
      if (peer.isAiAssistant) continue;
      if (seenIds.add(peer.id)) {
        targets.add(peer);
      }
    }
    return targets;
  }

  String _buildMessagePreview(LanguageProvider lang) {
    final msg = widget.message;
    if (msg.fileAttachment != null) {
      final name = msg.fileAttachment!.fileName.isNotEmpty
          ? msg.fileAttachment!.fileName
          : msg.text;
      return '📎 $name';
    }
    return StickerService.formatLastMessagePreview(
      msg.text,
      lang.tr('stickers'),
    );
  }

  Future<void> _handleForward(
    MessengerCoordinator coordinator,
    LanguageProvider lang,
    List<PeerModel> allTargets,
  ) async {
    if (_selectedPeerIds.isEmpty || _isSending) return;
    setState(() => _isSending = true);

    final recipients = allTargets
        .where((peer) => _selectedPeerIds.contains(peer.id))
        .toList(growable: false);

    try {
      await coordinator.forwardMessageToPeers(
        widget.message,
        recipients,
        note: _noteController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${lang.tr('forwardSuccess')} (${recipients.length})'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final ink = theme.isDark ? Colors.white : Colors.black87;

    final allTargets = _buildAvailableTargets(coordinator);
    final query = _searchQuery.trim().toLowerCase();
    final filteredTargets = allTargets
        .where((peer) {
          if (query.isEmpty) return true;
          return peer
                  .effectiveDisplayName(lang)
                  .toLowerCase()
                  .contains(query) ||
              peer.name.toLowerCase().contains(query) ||
              peer.ip.toLowerCase().contains(query) ||
              (peer.hostname?.toLowerCase().contains(query) ?? false);
        })
        .toList(growable: false);

    return GlassDialog(
      title: lang.tr('forwardTitle'),
      icon: Icons.shortcut_rounded,
      width: 440,
      scrollable: false,
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: Text(
            lang.tr('cancel'),
            style: TextStyle(color: ink.withValues(alpha: 0.7)),
          ),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: (_selectedPeerIds.isEmpty || _isSending)
              ? null
              : () => _handleForward(coordinator, lang, allTargets),
          icon: _isSending
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded, size: 15),
          label: Text(
            _selectedPeerIds.isEmpty
                ? lang.tr('forwardAction')
                : '${lang.tr('forwardAction')} (${_selectedPeerIds.length})',
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Message preview box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.06,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colors.accentBlue.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.message.fileAttachment != null
                      ? Icons.attach_file_rounded
                      : Icons.format_quote_rounded,
                  size: 16,
                  color: theme.colors.accentBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _buildMessagePreview(lang),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Search input
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(fontSize: 12.5, color: ink),
            decoration: InputDecoration(
              hintText: lang.tr('forwardSearchHint'),
              hintStyle: TextStyle(
                fontSize: 12,
                color: ink.withValues(alpha: 0.4),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 17,
                color: ink.withValues(alpha: 0.5),
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: ink.withValues(alpha: 0.5),
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Recipients list
          SizedBox(
            height: 220,
            child: filteredTargets.isEmpty
                ? Center(
                    child: Text(
                      lang.tr('noPeersFound'),
                      style: TextStyle(
                        fontSize: 12,
                        color: ink.withValues(alpha: 0.45),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredTargets.length,
                    itemBuilder: (context, index) {
                      final peer = filteredTargets[index];
                      final isChecked = _selectedPeerIds.contains(peer.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            if (isChecked) {
                              _selectedPeerIds.remove(peer.id);
                            } else {
                              _selectedPeerIds.add(peer.id);
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 5,
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: Checkbox(
                                  value: isChecked,
                                  activeColor: theme.colors.accentBlue,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedPeerIds.add(peer.id);
                                      } else {
                                        _selectedPeerIds.remove(peer.id);
                                      }
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              AppAvatar(peer: peer, size: 30, isCircle: true),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      peer.effectiveDisplayName(lang),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isChecked
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: ink,
                                      ),
                                    ),
                                    Text(
                                      peer.isGroup
                                          ? lang.tr('groupsHeader')
                                          : peer.ip,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: ink.withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),

          // Optional note input
          TextField(
            controller: _noteController,
            style: TextStyle(fontSize: 12.5, color: ink),
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              hintText: lang.tr('forwardNoteHint'),
              hintStyle: TextStyle(
                fontSize: 12,
                color: ink.withValues(alpha: 0.4),
              ),
              prefixIcon: Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: ink.withValues(alpha: 0.5),
              ),
              isDense: true,
              filled: true,
              fillColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 9,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
