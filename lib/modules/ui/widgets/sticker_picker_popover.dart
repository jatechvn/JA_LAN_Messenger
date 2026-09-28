import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/sticker_service.dart';
import 'sprite_sticker_widget.dart';

/// Popover bảng chọn nhãn dán (Sticker Picker) thiết kế chuẩn Bento Kính mờ
/// Hỗ trợ chuyển đổi giữa nhiều bộ sticker (Packs) qua thanh Dock dưới đáy
class _StickerPreviewTile extends StatefulWidget {
  final StickerItem sticker;
  final Widget child;
  final VoidCallback onTap;
  const _StickerPreviewTile({
    super.key,
    required this.sticker,
    required this.child,
    required this.onTap,
  });
  @override
  State<_StickerPreviewTile> createState() => _StickerPreviewTileState();
}

class _StickerPreviewTileState extends State<_StickerPreviewTile> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onHover: (value) => setState(() => _hovered = value),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: _hovered
            ? IgnorePointer(
                child: SpriteStickerWidget(
                  filePath: widget.sticker.isFromFile
                      ? widget.sticker.spritePath
                      : null,
                  assetPath: widget.sticker.isFromFile
                      ? null
                      : widget.sticker.spritePath,
                ),
              )
            : widget.child,
      ),
    ),
  );
}

class StickerPickerPopover extends StatefulWidget {
  final void Function(StickerItem sticker) onSelectSticker;
  final VoidCallback onClose;

  const StickerPickerPopover({
    super.key,
    required this.onSelectSticker,
    required this.onClose,
  });

  @override
  State<StickerPickerPopover> createState() => _StickerPickerPopoverState();
}

class _StickerPickerPopoverState extends State<StickerPickerPopover> {
  String _packName(StickerPack pack, LanguageProvider lang) =>
      pack.id == '0' || pack.id == 'pack_0'
      ? lang.tr('zaloOriginalPack')
      : pack.name;
  int _selectedPackIndex = 0;
  bool _isReloading = false;

  Future<void> _reloadPacks() async {
    if (_isReloading) return;
    setState(() => _isReloading = true);
    await StickerService().loadPacks();
    if (mounted) {
      setState(() => _isReloading = false);
    }
  }

  Widget _buildImageWidget(
    String path, {
    bool isFromFile = true,
    BoxFit fit = BoxFit.contain,
  }) {
    if (isFromFile) {
      final file = File(path);
      return Image.file(
        file,
        fit: fit,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: 24,
            color: Colors.white24,
          ),
        ),
      );
    } else {
      return Image.asset(
        path,
        fit: fit,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: 24,
            color: Colors.white24,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final stickerService = context.watch<StickerService>();
    final packs = stickerService.packs;

    final isDark = theme.isDark;
    final popoverBg =
        (isDark ? const Color(0xFF1E293B) : const Color(0xFFF7F8FA)).withValues(
          alpha: 0.98,
        );
    final borderColor = (isDark ? const Color(0x1FFFFFFF) : Colors.black)
        .withValues(alpha: isDark ? 0.8 : 0.08);

    final selectedIndex = _selectedPackIndex.clamp(
      0,
      packs.isEmpty ? 0 : packs.length - 1,
    );
    final currentPack = packs.isNotEmpty ? packs[selectedIndex] : null;

    return Container(
      width: 360,
      height: 290,
      decoration: BoxDecoration(
        color: popoverBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Pack Name / Stickers Title + Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sticky_note_2_rounded,
                      size: 16,
                      color: theme.colors.accentBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      currentPack != null
                          ? _packName(currentPack, lang)
                          : lang.tr('stickers'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: lang.tr('reloadStickers'),
                      child: InkWell(
                        onTap: _reloadPacks,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: _isReloading
                              ? SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: theme.colors.accentBlue,
                                  ),
                                )
                              : Icon(
                                  Icons.refresh_rounded,
                                  size: 15,
                                  color: isDark
                                      ? Colors.white54
                                      : Colors.black45,
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: widget.onClose,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.8,
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: isDark ? 0.08 : 0.06,
            ),
          ),

          // 2. Body: Sticker Grid
          Expanded(
            child: packs.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 38,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lang.tr('noStickersFound'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : Scrollbar(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1.0,
                          ),
                      itemCount: currentPack?.stickers.length ?? 0,
                      itemBuilder: (context, idx) {
                        final sticker = currentPack!.stickers[idx];
                        return _StickerPreviewTile(
                          key: ValueKey(sticker.token),
                          sticker: sticker,
                          onTap: () => widget.onSelectSticker(sticker),
                          child: _buildImageWidget(
                            sticker.previewPath,
                            isFromFile: sticker.isFromFile,
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // 3. Footer: Pack Selection Dock
          if (packs.isNotEmpty) ...[
            Divider(
              height: 1,
              thickness: 0.8,
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.08 : 0.06,
              ),
            ),
            Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: isDark ? 0.20 : 0.40,
              ),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: packs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, idx) {
                  final pack = packs[idx];
                  final isSelected = idx == selectedIndex;
                  return Tooltip(
                    message: _packName(pack, lang),
                    child: InkWell(
                      onTap: () {
                        if (_selectedPackIndex != idx) {
                          setState(() => _selectedPackIndex = idx);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 32,
                        height: 32,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colors.accentBlue.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(
                                  color: theme.colors.accentBlue,
                                  width: 1.5,
                                )
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: _buildImageWidget(
                            pack.iconPath,
                            isFromFile: pack.isFromFile,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
