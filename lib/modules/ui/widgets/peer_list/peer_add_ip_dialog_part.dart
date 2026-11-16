part of '../peer_list_view.dart';

class _AddIpDialog extends StatefulWidget {
  const _AddIpDialog();

  @override
  State<_AddIpDialog> createState() => _AddIpDialogState();
}

class _AddIpDialogState extends State<_AddIpDialog> {
  late final TextEditingController _controller;
  bool _isConnecting = false;
  String? _errorMessage;
  String? _connectingIp;

  @override
  void initState() {
    super.initState();
    final coordinator = context.read<MessengerCoordinator>();
    final prefixes = coordinator.suggestedIpPrefixes;
    final defaultPrefix = prefixes.isNotEmpty ? prefixes.first : '192.168.';
    _controller = TextEditingController(text: defaultPrefix);
    _controller.selection = TextSelection.collapsed(
      offset: defaultPrefix.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyPrefix(String prefix) {
    if (_isConnecting) return;
    final current = _controller.text.trim();
    final parts = current.split('.');
    String newText;
    if (parts.length >= 2) {
      final remainder = parts.sublist(2).join('.');
      newText = '$prefix$remainder';
    } else {
      newText = prefix;
    }
    setState(() {
      _errorMessage = null;
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newText.length);
    });
  }

  Future<void> _submit() async {
    final ip = _controller.text.trim();
    final lang = context.read<LanguageProvider>();
    final coordinator = context.read<MessengerCoordinator>();

    final target = NetworkUtils.parseIpv4Endpoint(ip, defaultListenerPort);
    if (target == null) {
      setState(() {
        _errorMessage = lang.tr('addIpInvalid');
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _connectingIp = ip;
    });

    final result = ip.contains(':')
        ? await coordinator.addManualEndpoint(target.ip, target.port)
        : await coordinator.addManualPeer(target.ip);
    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop();
      final name = result.peer?.displayName ?? ip;
      coordinator.showToast('addIpSuccessToast', ['$name ($ip)']);
      if (result.peer != null) {
        coordinator.selectPeer(result.peer);
      }
    } else if (result.isAlreadyExists) {
      Navigator.of(context).pop();
      final name = result.peer?.displayName ?? ip;
      coordinator.showToast('addIpAlreadyExists', ['$name ($ip)']);
      if (result.peer != null) {
        coordinator.selectPeer(result.peer);
      }
    } else if (result.isOwnIp) {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpOwnIp');
      });
    } else if (result.isInvalidIp) {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpInvalid');
      });
    } else {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpFailedToast', [ip]);
      });
    }
  }

  void _saveOffline() {
    final coordinator = context.read<MessengerCoordinator>();
    final targetIp = _connectingIp ?? _controller.text.trim();
    final target = NetworkUtils.parseIpv4Endpoint(
      targetIp,
      defaultListenerPort,
    );
    if (target == null) return;
    final peer = coordinator.addOfflineManualPeer(target.ip, target.port);
    Navigator.of(context).pop();
    coordinator.showToast('savedOfflineToast', [
      '${peer.displayName} ($targetIp)',
    ]);
    coordinator.selectPeer(peer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final prefixes = coordinator.suggestedIpPrefixes;
    final hintPrefix = prefixes.isNotEmpty ? prefixes.first : '192.168.';

    return GlassDialog(
      title: lang.tr('addIpTitle'),
      icon: Icons.person_add_alt_1_rounded,
      width: 420,
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.pop(context),
          child: Text(lang.tr('cancel')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _isConnecting ? null : _submit,
          child: _isConnecting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(lang.tr('connect')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lang.tr('addIpDesc'), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),

          // Suggestion chips
          if (prefixes.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  lang.tr('addIpSuggestedPrefix'),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    children: [
                      for (final p in prefixes)
                        ActionChip(
                          label: Text(
                            p,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colors.accentBlue,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colors.accentBlue.withValues(
                            alpha: 0.12,
                          ),
                          side: BorderSide(
                            color: theme.colors.accentBlue.withValues(
                              alpha: 0.35,
                            ),
                            width: 0.8,
                          ),
                          onPressed: _isConnecting
                              ? null
                              : () => _applyPrefix(p),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isConnecting,
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '${hintPrefix}1.100',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),

          if (_isConnecting) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr('addIpConnecting', [_connectingIp ?? '']),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colors.accentBlue,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_isConnecting &&
                      _connectingIp != null &&
                      _errorMessage ==
                          lang.tr('addIpFailedToast', [_connectingIp!])) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label: Text(
                          lang.tr('saveAsOfflineContact'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _saveOffline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
