class AiModelInfo {
  final String id;
  final String displayName;
  final bool supportsThinking;
  final bool supportsVision;
  final String description;

  const AiModelInfo({
    required this.id,
    required this.displayName,
    required this.supportsThinking,
    required this.supportsVision,
    required this.description,
  });

  static const List<AiModelInfo> supportedModels = [
    AiModelInfo(
      id: 'qwen2.5-vl:3b',
      displayName: 'Qwen 2.5 VL (3.8B Vision)',
      supportsThinking: false,
      supportsVision: true,
      description: 'Mô hình thị giác máy tính, phân tích hình ảnh và đồ thị',
    ),
    AiModelInfo(
      id: 'qwen3.5:4b',
      displayName: 'Qwen 3.5 (4.7B Reasoning)',
      supportsThinking: true,
      supportsVision: true,
      description:
          'Mô hình lập luận đa năng, hỗ trợ suy nghĩ (Thinking) & hình ảnh',
    ),
    AiModelInfo(
      id: 'qwen2.5-coder:3b',
      displayName: 'Qwen 2.5 Coder (3.4B Coding)',
      supportsThinking: false,
      supportsVision: false,
      description: 'Mô hình lập trình & trợ lý tốc độ cao, phản hồi ngắn gọn',
    ),
  ];

  static AiModelInfo get defaultModel => supportedModels.first;

  static List<AiModelInfo> _discoveredModels = [];

  static List<AiModelInfo> get currentModels => _discoveredModels.isNotEmpty
      ? List.unmodifiable(_discoveredModels)
      : supportedModels;

  /// Remove duplicate server/cache entries while preserving server order.
  /// Ollama tags are identifiers; display metadata may differ between scans,
  /// but the same identifier must only appear once in a selector.
  static List<AiModelInfo> deduplicate(Iterable<AiModelInfo> models) {
    final seen = <String>{};
    final result = <AiModelInfo>[];
    for (final model in models) {
      final id = model.id.trim();
      if (id.isEmpty || !seen.add(id.toLowerCase())) continue;
      result.add(model);
    }
    return result;
  }

  /// Select the user-facing server models. A JA-AI server may contain backup,
  /// alias, or experiment tags alongside the three supported production tags.
  static List<AiModelInfo> forServerSelection(Iterable<AiModelInfo> models) {
    final unique = deduplicate(models);
    final byId = <String, AiModelInfo>{
      for (final model in unique) model.id.trim().toLowerCase(): model,
    };
    final production = <AiModelInfo>[];
    for (final model in supportedModels) {
      final match = byId[model.id.toLowerCase()];
      if (match != null) production.add(model);
    }
    if (production.length == supportedModels.length) return production;

    return unique.where((model) {
      final id = model.id.toLowerCase();
      return !id.contains('.backup-') &&
          !id.endsWith('-nosystem') &&
          !id.endsWith(':latest');
    }).toList();
  }

  static void updateDiscoveredModels(List<AiModelInfo> models) {
    if (models.isEmpty) return;
    _discoveredModels = deduplicate(models);
  }

  static void resetDiscoveredModels() {
    _discoveredModels = [];
  }

  /// Auto-detect capabilities and format display name from model name/tag and optional metadata
  factory AiModelInfo.fromModelTag(
    String tag, {
    String? paramSize,
    String? family,
    List<String>? families,
    String? description,
  }) {
    for (final preset in supportedModels) {
      if (preset.id.toLowerCase() == tag.toLowerCase()) {
        return preset;
      }
    }

    final lower = tag.toLowerCase();
    final allFamilies = [
      if (family != null) family.toLowerCase(),
      if (families != null) ...families.map((f) => f.toLowerCase()),
    ];

    // 1. Detect Vision
    final supportsVision =
        lower.contains('-vl') ||
        lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('minicpm-v') ||
        lower.contains('bakllava') ||
        lower.contains('pixtral') ||
        lower.contains('qwen3.5') ||
        allFamilies.any(
          (f) =>
              f.contains('clip') ||
              f.contains('vision') ||
              f.contains('mllama'),
        );

    // 2. Detect Thinking / Reasoning
    final supportsThinking =
        lower.contains('r1') ||
        lower.contains('reason') ||
        lower.contains('thinking') ||
        lower.contains('qwq') ||
        lower.contains('qwen3.5') ||
        lower.contains('deepseek-r1');

    // 3. Format nice display name
    final name = _formatDisplayName(tag, paramSize);

    // 4. Generate description
    final desc =
        description ??
        _generateDescription(tag, supportsVision, supportsThinking, paramSize);

    return AiModelInfo(
      id: tag,
      displayName: name,
      supportsThinking: supportsThinking,
      supportsVision: supportsVision,
      description: desc,
    );
  }

  static String _formatDisplayName(String tag, String? paramSize) {
    var cleanTag = tag;
    String? tagParam;
    if (cleanTag.contains(':')) {
      final parts = cleanTag.split(':');
      cleanTag = parts[0];
      final suffix = parts[1];
      if (suffix != 'latest' && suffix.isNotEmpty) {
        if (RegExp(r'^\d+(\.\d+)?[bmkBMK]?$').hasMatch(suffix)) {
          tagParam = suffix.toUpperCase();
        } else {
          tagParam =
              suffix[0].toUpperCase() + suffix.substring(1).toLowerCase();
        }
      }
    }

    final words = cleanTag
        .split(RegExp(r'[-_]'))
        .map((w) {
          if (w.isEmpty) return '';
          final lw = w.toLowerCase();
          if (lw == 'vl') return 'VL';
          if (lw == 'ai') return 'AI';
          if (lw == 'coder') return 'Coder';
          if (lw == 'code') return 'Code';
          if (lw == 'r1') return 'R1';
          return w[0].toUpperCase() + w.substring(1);
        })
        .where((w) => w.isNotEmpty)
        .join(' ');

    final effectiveSize = paramSize?.isNotEmpty == true ? paramSize : tagParam;
    if (effectiveSize != null && !words.contains(effectiveSize)) {
      return '$words ($effectiveSize)';
    }
    return words;
  }

  static String _generateDescription(
    String tag,
    bool supportsVision,
    bool supportsThinking,
    String? paramSize,
  ) {
    final lower = tag.toLowerCase();
    final sizeStr = paramSize != null && paramSize.isNotEmpty
        ? ' ($paramSize)'
        : '';
    if (supportsThinking && supportsVision) {
      return 'Mô hình đa phương thức$sizeStr, hỗ trợ suy nghĩ sâu (Thinking) và phân tích hình ảnh.';
    } else if (supportsVision) {
      return 'Mô hình thị giác máy tính$sizeStr, phân tích hình ảnh và đồ thị.';
    } else if (supportsThinking) {
      return 'Mô hình lập luận logic$sizeStr, hỗ trợ suy nghĩ trước khi trả lời.';
    } else if (lower.contains('code') || lower.contains('coder')) {
      return 'Mô hình lập trình & giải thuật$sizeStr, hỗ trợ viết và sửa mã nguồn.';
    } else {
      return 'Mô hình ngôn ngữ tự nhiên đa năng$sizeStr.';
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'supportsThinking': supportsThinking,
    'supportsVision': supportsVision,
    'description': description,
  };

  factory AiModelInfo.fromJson(Map<String, dynamic> json) {
    return AiModelInfo(
      id: json['id'] as String? ?? 'qwen2.5-vl:3b',
      displayName: json['displayName'] as String? ?? 'Qwen 2.5 VL',
      supportsThinking: json['supportsThinking'] as bool? ?? false,
      supportsVision: json['supportsVision'] as bool? ?? false,
      description: json['description'] as String? ?? '',
    );
  }

  static AiModelInfo findById(String id) {
    if (id.trim().isEmpty) return defaultModel;
    for (final m in currentModels) {
      if (m.id == id) return m;
    }
    for (final m in supportedModels) {
      if (m.id == id) return m;
    }
    return AiModelInfo.fromModelTag(id);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiModelInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AiPreferences {
  final bool enabled;
  final String serverUrl;
  final String selectedModelId;
  final bool thinkingEnabled;
  final int contextLength;
  final int timeoutSeconds;
  final int maxQueue;

  const AiPreferences({
    this.enabled = true,
    this.serverUrl = 'http://172.21.175.20:11434',
    this.selectedModelId = 'qwen2.5-vl:3b',
    this.thinkingEnabled = false,
    this.contextLength = 4096,
    this.timeoutSeconds = 180,
    this.maxQueue = 4,
  });

  AiPreferences copyWith({
    bool? enabled,
    String? serverUrl,
    String? selectedModelId,
    bool? thinkingEnabled,
    int? contextLength,
    int? timeoutSeconds,
    int? maxQueue,
  }) {
    return AiPreferences(
      enabled: enabled ?? this.enabled,
      serverUrl: serverUrl ?? this.serverUrl,
      selectedModelId: selectedModelId ?? this.selectedModelId,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      contextLength: contextLength ?? this.contextLength,
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
      maxQueue: maxQueue ?? this.maxQueue,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'serverUrl': serverUrl,
    'selectedModelId': selectedModelId,
    'thinkingEnabled': thinkingEnabled,
    'contextLength': contextLength,
    'timeoutSeconds': timeoutSeconds,
    'maxQueue': maxQueue,
  };

  factory AiPreferences.fromJson(Map<String, dynamic> json) {
    return AiPreferences(
      enabled: json['enabled'] as bool? ?? true,
      serverUrl: json['serverUrl'] as String? ?? 'http://172.21.175.20:11434',
      selectedModelId: json['selectedModelId'] as String? ?? 'qwen3.5:4b',
      thinkingEnabled: json['thinkingEnabled'] as bool? ?? false,
      contextLength: json['contextLength'] as int? ?? 4096,
      timeoutSeconds: json['timeoutSeconds'] as int? ?? 180,
      maxQueue: json['maxQueue'] as int? ?? 4,
    );
  }
}
