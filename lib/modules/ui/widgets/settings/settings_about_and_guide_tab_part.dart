part of '../settings_dialog.dart';

mixin _SettingsAboutAndGuideTabMixin on _SettingsDialogStateBase {
  Widget _buildAboutTab(ThemeProvider theme, LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colors.accentBlue, theme.colors.accentCyan],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${lang.tr('versionLabel')} ${BuildInfo.version} (${BuildInfo.debugTimestamp})',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            lang.tr('aboutAppDesc1'),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            lang.tr('aboutAppDesc2'),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.04,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lang.tr('techInfoTitle'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentBlue,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• UDP Broadcast/Multicast Port: 36475 (224.0.64.75)',
                  style: TextStyle(fontSize: 11.5),
                ),
                const Text(
                  '• TCP Control/Chat Port: 6475',
                  style: TextStyle(fontSize: 11.5),
                ),
                const Text(
                  '• TCP File Transfer Port: 6476',
                  style: TextStyle(fontSize: 11.5),
                ),
                Text(
                  lang.tr('techInfoPureDart'),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserGuideTab(ThemeProvider theme, LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGuideItem(
            theme,
            step: '1',
            title: lang.tr('guideStep1Title'),
            desc: lang.tr('guideStep1Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '2',
            title: lang.tr('guideStep2Title'),
            desc: lang.tr('guideStep2Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '3',
            title: lang.tr('guideStep3Title'),
            desc: lang.tr('guideStep3Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '4',
            title: lang.tr('guideStep4Title'),
            desc: lang.tr('guideStep4Desc'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem(
    ThemeProvider theme, {
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: theme.colors.accentBlue,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.isDark ? Colors.white60 : Colors.black54,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
