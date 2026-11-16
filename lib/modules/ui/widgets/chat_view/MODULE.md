# Chat view sub-widgets (`lib/modules/ui/widgets/chat_view`)

`part` modules belonging to [../chat_view_panel.dart](../chat_view_panel.dart). Do not import these files standalone; import [../chat_view_panel.dart](../chat_view_panel.dart).

| Part File | Responsibility |
| :--- | :--- |
| [chat_header_part.dart](chat_header_part.dart) | `_ChatHeader`: peer/group bar, compact collapse, marquee name, Buzz/Call/File actions |
| [chat_pinned_and_quote_part.dart](chat_pinned_and_quote_part.dart) | `_PinnedMessagesBanner`, `_TypingIndicatorBubble`, `_QuoteCard` |
| [chat_message_bubble_part.dart](chat_message_bubble_part.dart) | `_MessageBubble`: text/markdown/sticker rendering, batch photo grids, context menu, delivery/seen receipts |
| [chat_message_accessories_part.dart](chat_message_accessories_part.dart) | `_AttachmentBatchFooter`, `_MessageQuickActionChips`, hover/Buzz buttons, `_MessageReactionsBar`, `_AiThinkingBox`, `_AttachmentPreview` |
| [chat_input_dock_part.dart](chat_input_dock_part.dart) | `_ChatInputDock`: composer, IME toggle/candidate overlay, `@` group mentions, responsive `< 360px` scaling |
| [staged_attachments_bar_part.dart](staged_attachments_bar_part.dart) | `StagedAttachmentsBar` (`public` widget): multi-file staging pills before sending |
| [chat_scroll_and_search_part.dart](chat_scroll_and_search_part.dart) | Empty states, `_ChatScrollControls`, unread/date separator banners, `_InChatSearchBar` (`Ctrl+F`) |
