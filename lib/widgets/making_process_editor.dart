import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../models/making_process_model.dart';

class MakingProcessEditor extends StatefulWidget {
  final MakingProcessModel? initialValue;

  const MakingProcessEditor({super.key, this.initialValue});

  @override
  State<MakingProcessEditor> createState() => MakingProcessEditorState();
}

class MakingProcessEditorState extends State<MakingProcessEditor> {
  late bool _enabled;
  late final TextEditingController _timeController;
  late final TextEditingController _skillController;
  late final TextEditingController _materialsController;
  late final TextEditingController _toolsController;
  late final TextEditingController _careController;
  late final TextEditingController _safetyController;
  final List<_StepControllers> _steps = [];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialValue;
    _enabled = initial?.enabled ?? false;
    _timeController = TextEditingController(text: initial?.estimatedTime ?? '');
    _skillController = TextEditingController(text: initial?.skillLevel ?? '');
    _materialsController = TextEditingController(
      text: initial?.materials.join(', ') ?? '',
    );
    _toolsController = TextEditingController(
      text: initial?.tools.join(', ') ?? '',
    );
    _careController = TextEditingController(
      text: initial?.careInstructions ?? '',
    );
    _safetyController = TextEditingController(text: initial?.safetyNotes ?? '');
    for (final step in initial?.steps ?? const <MakingStepModel>[]) {
      _steps.add(_StepControllers.fromModel(step));
    }
    if (_enabled && _steps.isEmpty) _steps.add(_StepControllers());
  }

  List<String> _commaList(String value) => value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();

  MakingProcessModel get value => MakingProcessModel(
    enabled: _enabled,
    estimatedTime: _timeController.text.trim(),
    skillLevel: _skillController.text.trim(),
    materials: _commaList(_materialsController.text),
    tools: _commaList(_toolsController.text),
    steps: _steps
        .map((step) => step.toModel())
        .where((step) => step.title.isNotEmpty || step.description.isNotEmpty)
        .toList(),
    careInstructions: _careController.text.trim(),
    safetyNotes: _safetyController.text.trim(),
  );

  bool validate() {
    if (!_enabled) return true;
    if (value.steps.isNotEmpty) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add at least one making step.')),
    );
    return false;
  }

  @override
  void dispose() {
    _timeController.dispose();
    _skillController.dispose();
    _materialsController.dispose();
    _toolsController.dispose();
    _careController.dispose();
    _safetyController.dispose();
    for (final step in _steps) {
      step.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String hint, {IconData? icon}) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightGrey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lightGrey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: AppColors.primary,
            title: const Text(
              "Show How It's Made",
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Share the real process so c+ART AI can explain it accurately.',
              style: TextStyle(fontSize: 11.5),
            ),
            value: _enabled,
            onChanged: (value) {
              setState(() {
                _enabled = value;
                if (_enabled && _steps.isEmpty) {
                  _steps.add(_StepControllers());
                }
              });
            },
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _materialsController,
              decoration: _decoration(
                'Materials, separated by commas',
                icon: Icons.category_outlined,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _toolsController,
              decoration: _decoration(
                'Tools, separated by commas',
                icon: Icons.handyman_outlined,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _timeController,
                    decoration: _decoration('Time, e.g. 4–6 hours'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _skillController,
                    decoration: _decoration('Skill level'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Making Steps',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...List.generate(_steps.length, (index) {
              final step = _steps[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.lightGrey),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.primary,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: step.title,
                              decoration: _decoration('Step title'),
                            ),
                          ),
                          if (_steps.length > 1)
                            IconButton(
                              tooltip: 'Remove step',
                              onPressed: () {
                                final removed = _steps.removeAt(index);
                                removed.dispose();
                                setState(() {});
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: step.description,
                        maxLines: 3,
                        decoration: _decoration(
                          'Explain what happens in this step',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            OutlinedButton.icon(
              onPressed: () => setState(() => _steps.add(_StepControllers())),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Step'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _careController,
              maxLines: 2,
              decoration: _decoration('Care instructions'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _safetyController,
              maxLines: 2,
              decoration: _decoration('Safety notes (optional)'),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepControllers {
  final TextEditingController title;
  final TextEditingController description;

  _StepControllers({String title = '', String description = ''})
    : title = TextEditingController(text: title),
      description = TextEditingController(text: description);

  factory _StepControllers.fromModel(MakingStepModel model) {
    return _StepControllers(title: model.title, description: model.description);
  }

  MakingStepModel toModel() => MakingStepModel(
    title: title.text.trim(),
    description: description.text.trim(),
  );

  void dispose() {
    title.dispose();
    description.dispose();
  }
}
