import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../services/ai_service.dart';
import '../../widgets/product_image.dart';

class HowItsMadeScreen extends StatefulWidget {
  final ProductModel product;

  const HowItsMadeScreen({super.key, required this.product});

  @override
  State<HowItsMadeScreen> createState() => _HowItsMadeScreenState();
}

class _HowItsMadeScreenState extends State<HowItsMadeScreen> {
  final AiService _ai = AiService();
  final TextEditingController _questionController = TextEditingController();
  String? _answer;

  @override
  void dispose() {
    _questionController.dispose();
    super.dispose();
  }

  void _ask([String? suggestion]) {
    final question = suggestion ?? _questionController.text.trim();
    if (question.isEmpty) return;
    _questionController.text = question;
    setState(
      () => _answer = _ai.answerMakingQuestion(widget.product, question),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final process = _ai.processFor(product);
    final sellerProvided = _ai.isSellerProvided(product);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text("How It's Made"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: ProductImage(
                      path: product.image,
                      fit: BoxFit.cover,
                      placeholder: const ColoredBox(
                        color: AppColors.lightGrey,
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sellerProvided
                            ? 'Based on information from the maker'
                            : 'General AI craft guide',
                        style: TextStyle(
                          color: sellerProvided
                              ? AppColors.success
                              : AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (!sellerProvided)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'The seller has not shared their exact process. This guide explains a common method, so the actual technique may differ.',
                style: TextStyle(fontSize: 12, height: 1.35),
              ),
            ),
          if (!sellerProvided) const SizedBox(height: 14),
          if (process.materials.isNotEmpty || process.tools.isNotEmpty)
            _InfoCard(
              title: 'Materials & Tools',
              icon: Icons.handyman_outlined,
              children: [
                if (process.materials.isNotEmpty)
                  _ChipList(label: 'Materials', values: process.materials),
                if (process.tools.isNotEmpty)
                  _ChipList(label: 'Tools', values: process.tools),
              ],
            ),
          if (process.estimatedTime.isNotEmpty || process.skillLevel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  if (process.estimatedTime.isNotEmpty)
                    Expanded(
                      child: _QuickFact(
                        icon: Icons.schedule_rounded,
                        label: 'Creation time',
                        value: process.estimatedTime,
                      ),
                    ),
                  if (process.estimatedTime.isNotEmpty &&
                      process.skillLevel.isNotEmpty)
                    const SizedBox(width: 10),
                  if (process.skillLevel.isNotEmpty)
                    Expanded(
                      child: _QuickFact(
                        icon: Icons.auto_awesome_rounded,
                        label: 'Skill level',
                        value: process.skillLevel,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          const Text(
            'Step-by-step process',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ...List.generate(process.steps.length, (index) {
            final step = process.steps[index];
            return _StepCard(
              number: index + 1,
              title: step.title,
              description: step.description,
              isLast: index == process.steps.length - 1,
            );
          }),
          if (process.careInstructions.isNotEmpty) ...[
            const SizedBox(height: 12),
            _TextInfoCard(
              title: 'Care instructions',
              icon: Icons.favorite_border_rounded,
              text: process.careInstructions,
            ),
          ],
          if (process.safetyNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            _TextInfoCard(
              title: 'Safety notes',
              icon: Icons.health_and_safety_outlined,
              text: process.safetyNotes,
            ),
          ],
          const SizedBox(height: 22),
          const Text(
            'Ask c+ART AI',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final question in const [
                'What materials are used?',
                'How long does it take?',
                'How should I care for it?',
              ])
                ActionChip(
                  label: Text(question),
                  onPressed: () => _ask(question),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _questionController,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _ask(),
            decoration: InputDecoration(
              hintText: 'Ask about the making process...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              suffixIcon: IconButton(
                onPressed: _ask,
                icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              ),
            ),
          ),
          if (_answer != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(_answer!, style: const TextStyle(height: 1.45)),
            ),
          ],
          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: AppColors.primary),
            const SizedBox(width: 7),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _ChipList extends StatelessWidget {
  final String label;
  final List<String> values;
  const _ChipList({required this.label, required this.values});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        Text(
          '$label:',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        ...values.map(
          (value) =>
              Chip(label: Text(value), visualDensity: VisualDensity.compact),
        ),
      ],
    ),
  );
}

class _QuickFact extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _QuickFact({
    required this.icon,
    required this.label,
    required this.value,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Row(
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final String description;
  final bool isLast;
  const _StepCard({
    required this.number,
    required this.title,
    required this.description,
    required this.isLast,
  });
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Column(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primary,
            child: Text(
              '$number',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (!isLast)
            Container(
              width: 2,
              height: 58,
              color: AppColors.primary.withValues(alpha: 0.25),
            ),
        ],
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.lightGrey),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _TextInfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;
  const _TextInfoCard({
    required this.title,
    required this.icon,
    required this.text,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            ],
          ),
        ),
      ],
    ),
  );
}
