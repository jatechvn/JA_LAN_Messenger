# UI widgets (`lib/modules/ui/widgets`)

Bento Glassmorphic desktop UI widgets hosted inside [MainMessengerWindow](../main_messenger_window.dart).

## Functional groups

- **Chat & Conversation View**:
  - [chat_view_panel.dart](chat_view_panel.dart) (`ChatViewPanel` & `_ChatViewPanelState`: scroll persistence, 100ms visible read-receipt dwell observer) + 7 cohesive `part` widgets in [chat_view/MODULE.md](chat_view/MODULE.md) (`_ChatHeader`, `_PinnedMessagesBanner`, `_MessageBubble`, `_MessageReactionsBar`, `_ChatInputDock`, `StagedAttachmentsBar`, `_InChatSearchBar`, `_ChatScrollControls`)
  - [conversation_details_panel.dart](conversation_details_panel.dart) (`ConversationDetailsPanel` — profile, shared media/files, group actions)
  - [markdown_message_view.dart](markdown_message_view.dart), [transfer_list_view.dart](transfer_list_view.dart)
- **Contacts, Search & Compact Mode**:
  - [peer_list_view.dart](peer_list_view.dart) (`PeerListView` & category filtering) + 5 cohesive `part` widgets in [peer_list/MODULE.md](peer_list/MODULE.md) (`_AddIpDialog` for `IPv4[:port]`, `_PinnedAllUsersTile`, `_GroupListTile`, `_PeerListTile`, `_ScanStatusBanner`/`_RadarBeacon`)
  - [compact_messenger_view.dart](compact_messenger_view.dart), [compact_sidebar.dart](compact_sidebar.dart)
- **Modals & Inspectors**:
  - [settings_dialog.dart](settings_dialog.dart) (`showSettingsDialog`, `SettingsDialog`, `_SettingsDialogStateBase`, state commit/reset) + 3 tab mixins (`part`): [settings/settings_advanced_tab_part.dart](settings/settings_advanced_tab_part.dart), [settings/settings_ota_tab_part.dart](settings/settings_ota_tab_part.dart), [settings/settings_about_and_guide_tab_part.dart](settings/settings_about_and_guide_tab_part.dart)
  - [glass_file_preview_dialog.dart](glass_file_preview_dialog.dart) (ZIP/XLSX structure, SHA-256, Hex dump, clipboard copy)
  - [glass_update_dialog.dart](glass_update_dialog.dart), [contact_profile_dialog.dart](contact_profile_dialog.dart), [create_group_dialog.dart](create_group_dialog.dart), [group_members_dialog.dart](group_members_dialog.dart), [forward_message_dialog.dart](forward_message_dialog.dart), [avatar_picker_dialog.dart](avatar_picker_dialog.dart), [close_action_dialog.dart](close_action_dialog.dart)
- **Glass, Animation & Power Primitives**:
  - [app_power_scope.dart](app_power_scope.dart), [glass_background.dart](glass_background.dart), [glass_components.dart](glass_components.dart), [glass_dialog.dart](glass_dialog.dart), [glass_dropdown.dart](glass_dropdown.dart), [glass_image_lightbox.dart](glass_image_lightbox.dart), [glass_search_history_field.dart](glass_search_history_field.dart), [bounce_marquee_text.dart](bounce_marquee_text.dart), [buzz_flash_overlay.dart](buzz_flash_overlay.dart), [app_avatar.dart](app_avatar.dart)
- **Stickers, Mentions & Built-in IME UI**:
  - [sprite_sticker_widget.dart](sprite_sticker_widget.dart), [sticker_picker_popover.dart](sticker_picker_popover.dart), [group_mention_picker.dart](group_mention_picker.dart), [ime_toggle_button.dart](ime_toggle_button.dart), [pinyin_candidate_bar.dart](pinyin_candidate_bar.dart)
