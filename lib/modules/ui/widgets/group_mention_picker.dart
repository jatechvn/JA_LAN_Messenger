import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/messenger_coordinator.dart';
import '../../theme/theme_provider.dart';
import 'app_avatar.dart';

/// Returns only the active @ token, not email addresses or IME pre-edit text.
({int start, int end, String query})? activeMention(TextEditingValue value) {
  final caret = value.selection.baseOffset;
  if (!value.selection.isCollapsed ||
      caret < 0 ||
      caret > value.text.length ||
      (value.composing.isValid && !value.composing.isCollapsed)) {
    return null;
  }
  final before = value.text.substring(0, caret);
  final match = RegExp(r'(^|\s)@([^@\n\r]{0,80})$').firstMatch(before);
  if (match == null) return null;
  return (
    start: match.start + match.group(1)!.length,
    end: caret,
    query: match.group(2)!,
  );
}

class GroupMentionPicker extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  const GroupMentionPicker({
    super.key,
    required this.controller,
    this.focusNode,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<MessengerCoordinator>();
    final selected = coordinator.selectedPeer;
    if (selected == null || !selected.isGroup || selected.isAllUsers) {
      return const SizedBox.shrink();
    }
    final theme = ThemeProvider.of(context);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final token = activeMention(value);
        if (token == null) return const SizedBox.shrink();
        final members = coordinator
            .groupMembers(selected.id)
            .where(
              (p) =>
                  p.id != 'me' &&
                  p.name.toLowerCase().contains(token.query.toLowerCase()),
            )
            .toList();
        if (members.isEmpty) return const SizedBox.shrink();
        return Material(
          color: theme.isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: members.length,
              itemBuilder: (context, index) {
                final peer = members[index];
                return ListTile(
                  dense: true,
                  leading: AppAvatar(peer: peer, size: 26),
                  title: Text(
                    '@${peer.name}',
                    style: TextStyle(
                      color: theme.isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    peer.ip,
                    style: TextStyle(
                      color: theme.isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  onTap: () {
                    final mention = '@${peer.name} ';
                    controller.value = TextEditingValue(
                      text: value.text.replaceRange(
                        token.start,
                        token.end,
                        mention,
                      ),
                      selection: TextSelection.collapsed(
                        offset: token.start + mention.length,
                      ),
                    );
                    onChanged?.call(controller.text);
                    focusNode?.requestFocus();
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}
