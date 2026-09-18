import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Supported application languages.
enum AppLanguage {
  vi('VI', 'Tiếng Việt', '🇻🇳'),
  en('EN', 'English', '🇬🇧'),
  cn('CN', '中文', '🇨🇳');

  final String code;
  final String label;
  final String flag;

  const AppLanguage(this.code, this.label, this.flag);
}

/// Language and localization provider for instant 1-click language switching.
class LanguageProvider extends ChangeNotifier {
  late AppLanguage _currentLanguage;

  LanguageProvider() {
    _currentLanguage = _detectSystemLanguage();
  }

  AppLanguage get currentLanguage => _currentLanguage;

  static AppLanguage _detectSystemLanguage() {
    try {
      final locale = Platform.localeName.toLowerCase();
      if (locale.startsWith('zh') || locale.contains('cn')) {
        return AppLanguage.cn;
      } else if (locale.startsWith('en')) {
        return AppLanguage.en;
      } else if (locale.startsWith('vi')) {
        return AppLanguage.vi;
      }
    } catch (_) {}
    return AppLanguage.vi; // Default to Vietnamese
  }

  /// Cycles to the next language: VI -> EN -> CN -> VI
  void cycleLanguage() {
    switch (_currentLanguage) {
      case AppLanguage.vi:
        _currentLanguage = AppLanguage.en;
        break;
      case AppLanguage.en:
        _currentLanguage = AppLanguage.cn;
        break;
      case AppLanguage.cn:
        _currentLanguage = AppLanguage.vi;
        break;
    }
    notifyListeners();
  }

  void setLanguage(AppLanguage language) {
    if (_currentLanguage != language) {
      _currentLanguage = language;
      notifyListeners();
    }
  }

  /// Localized Tab Labels
  List<String> get tabLabels {
    switch (_currentLanguage) {
      case AppLanguage.vi:
        return const [
          'Tổng quan',
          'Linh kiện',
          'Terminal',
          'Thiết bị',
          'Băng thông',
        ];
      case AppLanguage.en:
        return const [
          'Overview',
          'Components',
          'Terminal',
          'Devices',
          'Bandwidth',
        ];
      case AppLanguage.cn:
        return const ['概览', '组件', '终端', '设备', '带宽'];
    }
  }

  /// Localized String dictionary lookup
  String t(String key) {
    final entry = _translations[key];
    if (entry == null) return key;
    return entry[_currentLanguage.code.toLowerCase()] ?? entry['vi'] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'perf_tooltip': {
      'vi': 'Chế độ đồ họa & Hiệu năng máy',
      'en': 'Graphic Tier & Hardware Profile',
      'cn': '图形档位与硬件配置',
    },
    'lang_tooltip': {
      'vi': 'Chuyển ngôn ngữ nhanh (EN/VI/CN)',
      'en': 'Quick Language Switch (EN/VI/CN)',
      'cn': '快速切换语言 (EN/VI/CN)',
    },
    'theme_tooltip': {
      'vi': 'Chuyển giao diện Sáng / Tối',
      'en': 'Toggle Light / Dark Theme',
      'cn': '切换深色/浅色主题',
    },
    'settings_tooltip': {
      'vi': 'Cài đặt hiệu ứng kính mờ',
      'en': 'Glass Tuning Settings',
      'cn': '毛玻璃微调设置',
    },
    'status_live': {
      'vi': 'LIVE • 8090',
      'en': 'LIVE • 8090',
      'cn': '运行 • 8090',
    },
    'status_standby': {'vi': 'STANDBY', 'en': 'STANDBY', 'cn': '待机'},
    'status_devices': {'vi': '3 dev', 'en': '3 dev', 'cn': '3设备'},
    'lang_changed_msg': {
      'vi': '🌐 Đã chuyển ngôn ngữ: Tiếng Việt',
      'en': '🌐 Language switched: English',
      'cn': '🌐 语言已切换: 中文',
    },
    'settings_dialog_title': {
      'vi': 'Cài đặt Glassmorphism & Giao diện',
      'en': 'Glassmorphism & UI Settings',
      'cn': '毛玻璃效果与界面设置',
    },
    'settings_card_header': {
      'vi': 'Điều chỉnh Liquid Glass & Bento Card',
      'en': 'Liquid Glass & Bento Card Tuning',
      'cn': '液体玻璃与 Bento 卡片微调',
    },
    'settings_default': {'vi': 'Mặc định', 'en': 'Default', 'cn': '默认'},
    'settings_card_blur': {
      'vi': 'Độ mờ khối Bento (Card Blur)',
      'en': 'Bento Card Blur',
      'cn': 'Bento 卡片模糊度',
    },
    'settings_card_opacity': {
      'vi': 'Độ đục khối Bento (Card Opacity)',
      'en': 'Bento Card Opacity',
      'cn': 'Bento 卡片不透明度',
    },
    'settings_dialog_blur': {
      'vi': 'Độ mờ Hộp thoại (Dialog Blur)',
      'en': 'Dialog Blur',
      'cn': '弹窗模糊度',
    },
    'settings_dialog_opacity': {
      'vi': 'Độ đục Hộp thoại (Dialog Opacity)',
      'en': 'Dialog Opacity',
      'cn': '弹窗不透明度',
    },
    'settings_dropdown_blur': {
      'vi': 'Độ mờ Bảng chọn (Dropdown Blur)',
      'en': 'Dropdown Blur',
      'cn': '下拉菜单模糊度',
    },
    'settings_dropdown_opacity': {
      'vi': 'Độ đục Bảng chọn (Dropdown Opacity)',
      'en': 'Dropdown Opacity',
      'cn': '下拉菜单不透明度',
    },
    'action_cancel': {'vi': 'Hủy', 'en': 'Cancel', 'cn': '取消'},
    'action_save': {'vi': 'Lưu Cài Đặt', 'en': 'Save Settings', 'cn': '保存设置'},
    'theme_light': {'vi': 'Sáng', 'en': 'Light', 'cn': '浅色'},
    'theme_dark': {'vi': 'Tối', 'en': 'Dark', 'cn': '深色'},
    'settings_btn_label': {'vi': 'Cài đặt', 'en': 'Settings', 'cn': '设置'},
    'tab_settings_ui': {
      'vi': 'Kính mờ & Giao diện',
      'en': 'Glass & UI',
      'cn': '界面与毛玻璃',
    },
    'tab_user_guide': {
      'vi': 'Hướng dẫn sử dụng',
      'en': 'User Guide',
      'cn': '使用指南',
    },
    'tab_about': {'vi': 'Giới thiệu', 'en': 'About', 'cn': '关于应用'},
    'guide_shortcuts_title': {
      'vi': 'Phím tắt toàn cục',
      'en': 'Global Shortcuts',
      'cn': '全局快捷键',
    },
    'guide_shortcuts_desc': {
      'vi':
          '• Ctrl + K (hoặc Cmd + K): Mở nhanh Command Palette từ mọi nơi.\n• Esc: Đóng nhanh hộp thoại kính mờ, menu dropdown hoặc search palette.\n• Dùng các tab Overview, Components, Devices và Bandwidth để kiểm tra từng nhóm widget sau mỗi lần refactor.',
      'en':
          '• Ctrl + K (or Cmd + K): Open Command Palette from anywhere in the app.\n• Esc: Instantly dismiss glass dialogs, dropdowns, or search palettes.\n• Use Overview, Components, Devices, and Bandwidth to validate each widget family after refactors.',
      'cn':
          '• Ctrl + K (或 Cmd + K): 随时打开全局命令搜索面板。\n• Esc: 快速关闭毛玻璃弹窗、下拉菜单或命令面板。\n• 使用 Overview、Components、Devices 和 Bandwidth 检查每组组件。',
    },
    'guide_topbar_title': {
      'vi': 'Tương tác TopBar phóng lớn',
      'en': 'TopBar Hover Expansion',
      'cn': '顶栏悬停放大交互',
    },
    'guide_topbar_desc': {
      'vi':
          'Rê chuột qua các nút Cấu hình máy, Ngôn ngữ, Sáng/Tối và Cài đặt để phóng lớn (scale 1.05) và trượt mượt hiển thị nhãn đầy đủ.',
      'en':
          'Hover over Graphic Tier, Language, Light/Dark, and Settings buttons to scale up (1.05x) and smoothly reveal full labels.',
      'cn': '悬停于图形档位、语言、明暗主题与设置按钮，可放大 (1.05x) 并平滑展开完整标签文字。',
    },
    'guide_tier_title': {
      'vi': 'Phân tầng đồ họa máy tính',
      'en': 'Hardware Graphic Tiers',
      'cn': '硬件图形性能档位',
    },
    'guide_tier_desc': {
      'vi':
          '• Ultra: 120 FPS, tối đa hiệu ứng làm mờ Acrylic/Aero.\n• Balanced: 60 FPS, tối ưu hóa cho Laptop và tiết kiệm pin.\n• Lite: Tắt toàn bộ làm mờ, không giật lag trên máy yếu.',
      'en':
          '• Ultra: 120 FPS, maximum Acrylic/Aero glassmorphism.\n• Balanced: 60 FPS, optimized for laptops and battery.\n• Lite: Zero blur, ultra-low power consumption on weak hardware.',
      'cn':
          '• Ultra: 120 FPS，最大化 Acrylic/Aero 毛玻璃模糊效果。\n• Balanced: 60 FPS，专为笔记本与省电优化。\n• Lite: 关闭全部模糊，低端设备流畅不卡顿。',
    },
    'guide_scroll_title': {
      'vi': 'Cuộn bật nảy & Bảng chọn dài',
      'en': 'Bouncing Scroll & Dropdown',
      'cn': '弹性滚动与长下拉列表',
    },
    'guide_scroll_desc': {
      'vi':
          'BouncingScrollPhysics mang lại cảm giác cuộn đàn hồi cao cấp. Bảng chọn kính mờ GlassDropdown tự động kích hoạt ô tìm kiếm trực tiếp khi danh sách vượt quá 5 mục.',
      'en':
          'BouncingScrollPhysics delivers premium elastic physics. GlassDropdown automatically embeds a live search box when items exceed 5.',
      'cn':
          'BouncingScrollPhysics 带来高端弹性物理滚动。当列表超过 5 项时，GlassDropdown 自动启用即时搜索输入框。',
    },
    'about_app_name': {
      'vi': 'JA Mini Showcase',
      'en': 'JA Mini Showcase',
      'cn': 'JA Mini Showcase',
    },
    'about_app_desc': {
      'vi':
          'Bộ showcase Flutter Desktop cho JA-HUB Bento Glassmorphism, Dynamic Island navigation, live glass tuning, Command Palette, bộ lọc thiết bị và các mẫu motion UI tái sử dụng.',
      'en':
          'Flutter Desktop showcase for JA-HUB Bento Glassmorphism, Dynamic Island navigation, live glass tuning, Command Palette, device filters, and reusable UI motion patterns.',
      'cn':
          '面向 JA-HUB 的 Flutter Desktop 展示工程，涵盖 Bento 毛玻璃、Dynamic Island 导航、实时玻璃调校、Command Palette、设备筛选与可复用 UI 动效。',
    },
    'about_dev_title': {
      'vi': 'Thông tin phát triển & Bản quyền',
      'en': 'Development & Licensing',
      'cn': '开发信息与授权',
    },
    'about_sys_title': {
      'vi': 'Môi trường hệ thống & Phần cứng',
      'en': 'System & Hardware Runtime',
      'cn': '系统环境与硬件运行时',
    },
    'terminal_title': {
      'vi': 'Giả Lập Dòng Lệnh',
      'en': 'Command Terminal',
      'cn': '命令终端',
    },
    'terminal_clear': {
      'vi': 'Xóa màn hình',
      'en': 'Clear console',
      'cn': '清空控制台',
    },
    'terminal_copy': {
      'vi': 'Sao chép nhật ký',
      'en': 'Copy console log',
      'cn': '复制日志',
    },
    'terminal_copied': {
      'vi': 'Đã sao chép nhật ký vào bộ nhớ tạm',
      'en': 'Terminal log copied to clipboard',
      'cn': '终端日志已复制到剪贴板',
    },
    'terminal_autoscroll': {
      'vi': 'Tự động cuộn',
      'en': 'Auto-scroll',
      'cn': '自动滚动',
    },
    'terminal_prompt_hint': {
      'vi': 'Nhập lệnh (gõ help để xem danh sách)...',
      'en': 'Enter command (type help for list)...',
      'cn': '输入命令 (输入 help 查看列表)...',
    },
  };
}

extension LanguageExtension on BuildContext {
  LanguageProvider get language => watch<LanguageProvider>();
  String t(String key) => watch<LanguageProvider>().t(key);
}
