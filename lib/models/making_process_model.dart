class MakingStepModel {
  final String title;
  final String description;

  const MakingStepModel({required this.title, required this.description});

  Map<String, dynamic> toMap() => {'title': title, 'description': description};

  factory MakingStepModel.fromMap(Map<String, dynamic> map) {
    return MakingStepModel(
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
    );
  }
}

class MakingProcessModel {
  final bool enabled;
  final String estimatedTime;
  final String skillLevel;
  final List<String> materials;
  final List<String> tools;
  final List<MakingStepModel> steps;
  final String careInstructions;
  final String safetyNotes;

  const MakingProcessModel({
    this.enabled = false,
    this.estimatedTime = '',
    this.skillLevel = '',
    this.materials = const [],
    this.tools = const [],
    this.steps = const [],
    this.careInstructions = '',
    this.safetyNotes = '',
  });

  bool get hasSellerProcess => enabled && steps.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'enabled': enabled,
    'estimatedTime': estimatedTime,
    'skillLevel': skillLevel,
    'materials': materials,
    'tools': tools,
    'steps': steps.map((step) => step.toMap()).toList(),
    'careInstructions': careInstructions,
    'safetyNotes': safetyNotes,
    'source': 'seller',
  };

  factory MakingProcessModel.fromMap(Map<String, dynamic> map) {
    return MakingProcessModel(
      enabled: map['enabled'] as bool? ?? false,
      estimatedTime: map['estimatedTime'] as String? ?? '',
      skillLevel: map['skillLevel'] as String? ?? '',
      materials: ((map['materials'] as List?) ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      tools: ((map['tools'] as List?) ?? [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      steps: ((map['steps'] as List?) ?? [])
          .map(
            (item) =>
                MakingStepModel.fromMap(Map<String, dynamic>.from(item as Map)),
          )
          .where((step) => step.title.isNotEmpty || step.description.isNotEmpty)
          .toList(),
      careInstructions: map['careInstructions'] as String? ?? '',
      safetyNotes: map['safetyNotes'] as String? ?? '',
    );
  }
}
