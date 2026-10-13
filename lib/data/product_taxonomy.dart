import 'package:flutter/material.dart';

/// A customer-facing main category, e.g. "Flowers & Bouquets". Each
/// one groups a handful of subcategories a seller can pick from
/// (stored on the categories table as category_group / name).
class MainCategory {
  final String name;
  final IconData icon;
  final List<String> subcategories;

  const MainCategory({
    required this.name,
    required this.icon,
    required this.subcategories,
  });
}

/// The 8 main categories customers browse by. Answers "what am I
/// buying?" — how it was made, what it's made of, and why someone's
/// buying it are separate filters (see [craftTypes], [materials],
/// [occasions] below), not part of this list.
const List<MainCategory> mainCategories = [
  MainCategory(
    name: "Flowers & Bouquets",
    icon: Icons.local_florist_outlined,
    subcategories: [
      "Money Bouquet",
      "Chocolate Bouquet",
      "Makeup Bouquet",
      "Crochet Flower Bouquet",
      "Paper Flower Bouquet",
      "Dried Flower Bouquet",
    ],
  ),
  MainCategory(
    name: "Gifts & Personalized",
    icon: Icons.card_giftcard_outlined,
    subcategories: [
      "Personalized Gifts",
      "Gift Boxes",
      "Handmade Cards",
      "Photo/Memory Gifts",
      "Customized Crafts",
    ],
  ),
  MainCategory(
    name: "Jewelry & Accessories",
    icon: Icons.diamond_outlined,
    subcategories: [
      "Bracelets",
      "Necklaces",
      "Earrings",
      "Rings",
      "Keychains",
      "Hair Accessories",
    ],
  ),
  MainCategory(
    name: "Home & Room Decor",
    icon: Icons.home_outlined,
    subcategories: [
      "Wall Decor",
      "Table Decor",
      "Hanging Decor",
      "Plant/Pot Decor",
      "Handmade Figurines",
      "Room Accessories",
    ],
  ),
  MainCategory(
    name: "Plushies & Textile",
    icon: Icons.emoji_nature_outlined,
    subcategories: [
      "Crochet",
      "Knitted Items",
      "Handmade Plushies",
      "Embroidery",
      "Sewing",
      "Felt Crafts",
    ],
  ),
  MainCategory(
    name: "Paper & Stationery",
    icon: Icons.description_outlined,
    subcategories: [
      "Origami",
      "Scrapbooking",
      "Handmade Cards",
      "Bookmarks",
      "Calligraphy",
      "Bookbinding",
    ],
  ),
  MainCategory(
    name: "Wood, Clay & Leather",
    icon: Icons.forest_outlined,
    subcategories: [
      "Wood Crafts",
      "Pottery & Ceramics",
      "Sculptures",
      "Leather Crafts",
      "Clay Crafts",
    ],
  ),
  MainCategory(
    name: "Eco & Recycled",
    icon: Icons.eco_outlined,
    subcategories: [
      "Recycled Keychains",
      "Recycled Decor",
      "Upcycled Accessories",
      "Recycled Paper Crafts",
      "Bottle/Can Crafts",
    ],
  ),
];

/// "How was it made?" — an optional filter/tag on a product,
/// independent of which main category it's listed under.
const List<String> craftTypes = [
  "Crochet",
  "Knitting",
  "Sewing",
  "Embroidery",
  "Weaving",
  "Felting",
  "Woodworking",
  "Pottery & Ceramics",
  "Sculpting",
  "Leatherworking",
  "Origami",
  "Scrapbooking",
  "Calligraphy",
  "Bookbinding",
  "Beadwork",
  "Wire Wrapping",
  "Metalsmithing",
];

/// "What is it made from?"
const List<String> materials = [
  "Yarn",
  "Fabric",
  "Wood",
  "Paper",
  "Clay",
  "Polymer Clay",
  "Leather",
  "Metal",
  "Glass",
  "Beads",
  "Wax",
  "Recycled Materials",
  "Mixed Materials",
];

/// "Why is someone buying it?"
const List<String> occasions = [
  "Birthday",
  "Anniversary",
  "Wedding",
  "Graduation",
  "Valentine's Day",
  "Christmas",
  "Baby Shower",
  "Get Well Soon",
  "Congratulations",
  "Just Because",
];

/// Freeform-ish descriptive tags a seller can attach to a listing.
const List<String> productTagOptions = [
  "Handmade",
  "Customizable",
  "Gift-Ready",
  "Eco-Friendly",
  "Limited Edition",
  "Made to Order",
  "One of a Kind",
];
