import 'package:flutter/material.dart';

import '../../constants/app_colors.dart';
import '../../models/product_model.dart';
import '../../repositories/product_repository.dart';
import '../../services/ai_service.dart';
import '../../widgets/product_image.dart';
import '../customer/how_its_made_screen.dart';
import '../customer/product_details_screen.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final AiService _ai = AiService();
  final ProductRepository _products = ProductRepository();
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_AssistantTurn> _turns = [];
  List<ProductModel> _catalog = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final products = await _products.getAllProducts();
      if (!mounted) return;
      setState(() {
        _catalog = products;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _submit([String? suggestion]) {
    final question = (suggestion ?? _controller.text).trim();
    if (question.isEmpty || _loading) return;
    _controller.clear();
    final matches = _ai.recommendProducts(_catalog, question);
    setState(() {
      _turns.add(
        _AssistantTurn(
          question: question,
          answer: _ai.shoppingAnswer(question, matches),
          products: matches,
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ask AI', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(
              'Grounded in available marketplace products',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.normal),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  const _AssistantBubble(
                    text:
                        'Tell me the occasion, budget, craft type, material, or style you want. I will recommend available handmade products.',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final suggestion in const [
                        'Birthday gift under ₱500',
                        'Show crochet flowers',
                        'Popular home decorations',
                      ])
                        ActionChip(
                          label: Text(suggestion),
                          onPressed: _loading
                              ? null
                              : () => _submit(suggestion),
                        ),
                    ],
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ..._turns.expand(
                    (turn) => [
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 280),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            turn.question,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _AssistantBubble(text: turn.answer),
                      if (turn.products.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 205,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: turn.products.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, index) =>
                                _RecommendationCard(
                                  product: turn.products[index],
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
              color: Colors.white,
              child: TextField(
                controller: _controller,
                enabled: !_loading,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: 'Ask for a handmade product...',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    onPressed: _loading ? null : _submit,
                    icon: const Icon(
                      Icons.send_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantTurn {
  final String question;
  final String answer;
  final List<ProductModel> products;
  const _AssistantTurn({
    required this.question,
    required this.answer,
    required this.products,
  });
}

class _AssistantBubble extends StatelessWidget {
  final String text;
  const _AssistantBubble({required this.text});
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 315),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Flexible(child: Text(text, style: const TextStyle(height: 1.4))),
        ],
      ),
    ),
  );
}

class _RecommendationCard extends StatelessWidget {
  final ProductModel product;
  const _RecommendationCard({required this.product});
  @override
  Widget build(BuildContext context) => Container(
    width: 160,
    padding: const EdgeInsets.all(9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.lightGrey),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: double.infinity,
            height: 88,
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
        const SizedBox(height: 6),
        Text(
          product.productName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        Text(
          '₱${product.price.toStringAsFixed(0)} · ${product.rating.toStringAsFixed(1)} ★',
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HowItsMadeScreen(product: product),
                  ),
                ),
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text('How made', style: TextStyle(fontSize: 9)),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProductDetailsScreen(product: product),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('View', style: TextStyle(fontSize: 10)),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
