import '../models/making_process_model.dart';
import '../models/product_model.dart';

class AiService {
  List<ProductModel> recommendProducts(
    List<ProductModel> products,
    String question, {
    int limit = 5,
  }) {
    final query = question.toLowerCase();
    final budgetMatch = RegExp(
      r'(?:under|below|less than|budget|max(?:imum)?)[^0-9]*(\d+(?:\.\d+)?)',
    ).firstMatch(query);
    final budget = budgetMatch == null
        ? null
        : double.tryParse(budgetMatch.group(1)!);
    const ignored = {
      'show',
      'find',
      'need',
      'want',
      'please',
      'product',
      'products',
      'handmade',
      'craft',
      'gift',
      'for',
      'the',
      'and',
      'with',
      'under',
      'below',
      'less',
      'than',
      'budget',
      'maximum',
      'max',
      'something',
    };
    final words = query
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 2 && !ignored.contains(word))
        .toSet();

    final scored = <(ProductModel, int)>[];
    for (final product in products) {
      if (product.stock <= 0 || (budget != null && product.price > budget)) {
        continue;
      }
      final searchable = [
        product.productName,
        product.description,
        product.categoryName ?? '',
        product.categoryGroup ?? '',
        product.craftType ?? '',
        product.material ?? '',
        product.occasion ?? '',
        ...product.tags,
      ].join(' ').toLowerCase();
      var score = 0;
      for (final word in words) {
        if (searchable.contains(word)) score += 3;
      }
      if (query.contains('popular') || query.contains('best seller')) {
        score += product.totalSold.clamp(0, 20);
      }
      if (query.contains('rated') || query.contains('rating')) {
        score += product.rating.round() * 2;
      }
      scored.add((product, score));
    }
    scored.sort((a, b) {
      final scoreCompare = b.$2.compareTo(a.$2);
      if (scoreCompare != 0) return scoreCompare;
      final ratingCompare = b.$1.rating.compareTo(a.$1.rating);
      if (ratingCompare != 0) return ratingCompare;
      return b.$1.totalSold.compareTo(a.$1.totalSold);
    });
    return scored.take(limit).map((entry) => entry.$1).toList();
  }

  String shoppingAnswer(String question, List<ProductModel> matches) {
    if (matches.isEmpty) {
      return 'I could not find an available product matching that request. Try changing the craft type, occasion, or budget.';
    }
    final budget = RegExp(
      r'(?:under|below|budget)[^0-9]*(\d+)',
    ).firstMatch(question.toLowerCase());
    final budgetText = budget == null
        ? ''
        : ' within your ₱${budget.group(1)} budget';
    return 'I found ${matches.length} available handmade ${matches.length == 1 ? 'product' : 'products'}$budgetText. Tap a recommendation to view its details or learn how it was made.';
  }

  MakingProcessModel processFor(ProductModel product) {
    final sellerProcess = product.makingProcess;
    if (sellerProcess?.hasSellerProcess == true) return sellerProcess!;

    final craft = (product.craftType?.trim().isNotEmpty == true)
        ? product.craftType!.trim()
        : product.categoryName?.trim().isNotEmpty == true
        ? product.categoryName!.trim()
        : 'handmade craft';
    final material = product.material?.trim() ?? '';

    return MakingProcessModel(
      enabled: true,
      skillLevel: 'Varies by maker',
      materials: material.isEmpty ? const [] : [material],
      steps: [
        MakingStepModel(
          title: 'Plan the design',
          description:
              'The maker plans the shape, size, colors, and finish for the $craft.',
        ),
        MakingStepModel(
          title: 'Prepare the materials',
          description: material.isEmpty
              ? 'The materials are selected, measured, and prepared for crafting.'
              : '$material is selected, measured, and prepared for crafting.',
        ),
        MakingStepModel(
          title: 'Create the main form',
          description:
              'The maker builds the piece by hand using techniques commonly used for $craft.',
        ),
        const MakingStepModel(
          title: 'Refine the details',
          description:
              'Edges, joins, decorative details, and other visible areas are carefully finished.',
        ),
        const MakingStepModel(
          title: 'Inspect and finish',
          description:
              'The completed item is checked, cleaned, and prepared for packaging.',
        ),
      ],
      careInstructions:
          'Follow the seller’s product description or contact the seller for exact care instructions.',
    );
  }

  bool isSellerProvided(ProductModel product) =>
      product.makingProcess?.hasSellerProcess == true;

  String answerMakingQuestion(ProductModel product, String question) {
    final process = processFor(product);
    final query = question.trim().toLowerCase();
    final sourceNote = isSellerProvided(product)
        ? 'This answer uses information provided by the maker.'
        : 'This is a general craft guide. The seller’s actual method may differ.';

    if (query.contains('material')) {
      final value = process.materials.isEmpty
          ? 'The seller has not listed the exact materials.'
          : 'Materials: ${process.materials.join(', ')}.';
      return '$value\n\n$sourceNote';
    }
    if (query.contains('tool')) {
      final value = process.tools.isEmpty
          ? 'The seller has not listed the exact tools.'
          : 'Tools: ${process.tools.join(', ')}.';
      return '$value\n\n$sourceNote';
    }
    if (query.contains('long') || query.contains('time')) {
      final value = process.estimatedTime.isEmpty
          ? 'The maker has not provided an estimated creation time.'
          : 'Estimated creation time: ${process.estimatedTime}.';
      return '$value\n\n$sourceNote';
    }
    if (query.contains('care') ||
        query.contains('clean') ||
        query.contains('wash')) {
      final value = process.careInstructions.isEmpty
          ? 'Exact care instructions are not available. Ask the seller before cleaning the item.'
          : process.careInstructions;
      return '$value\n\n$sourceNote';
    }
    if (query.contains('safe') || query.contains('safety')) {
      final value = process.safetyNotes.isEmpty
          ? 'No specific safety notes were provided. Use handmade items only as intended.'
          : process.safetyNotes;
      return '$value\n\n$sourceNote';
    }

    return 'The process has ${process.steps.length} main steps. Open the numbered guide above for the complete procedure.\n\n$sourceNote';
  }
}
