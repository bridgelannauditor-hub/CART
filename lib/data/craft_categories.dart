import 'package:flutter/material.dart';

class CraftCategoryItem {
  final String name;
  final String description;
  final IconData icon;

  const CraftCategoryItem({
    required this.name,
    required this.description,
    required this.icon,
  });
}

class CraftCategoryGroup {
  final String title;
  final String previewVideoUrl;
  final List<CraftCategoryItem> items;

  const CraftCategoryGroup({
    required this.title,
    required this.previewVideoUrl,
    required this.items,
  });
}

// NOTE: previewVideoUrl values below are placeholder public sample
// clips (Google's standard test videos) so the video-preview cards
// are fully functional out of the box. Swap these for real craft
// footage whenever it's available.
const List<CraftCategoryGroup> craftCategoryGroups = [
  CraftCategoryGroup(
    title: "Fiber and Textile Crafts",
    previewVideoUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
    items: [
      CraftCategoryItem(
        name: "Knitting",
        description: "Using two needles to loop yarn together into fabric.",
        icon: Icons.texture_outlined,
      ),
      CraftCategoryItem(
        name: "Crochet",
        description: "Using a single hooked needle to interlock loops of yarn.",
        icon: Icons.gesture_outlined,
      ),
      CraftCategoryItem(
        name: "Sewing",
        description:
            "Joining fabric pieces together using a needle and thread.",
        icon: Icons.content_cut_outlined,
      ),
      CraftCategoryItem(
        name: "Embroidery",
        description:
            "Decorating fabric with decorative stitching using a needle and thread.",
        icon: Icons.auto_awesome_outlined,
      ),
      CraftCategoryItem(
        name: "Weaving",
        description:
            "Interlacing two sets of vertical and horizontal threads on a loom.",
        icon: Icons.grid_on_outlined,
      ),
      CraftCategoryItem(
        name: "Felting",
        description: "Matting and pressing loose wool fibers together.",
        icon: Icons.blur_on_outlined,
      ),
    ],
  ),
  CraftCategoryGroup(
    title: "Hard Materials and Sculpture",
    previewVideoUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
    items: [
      CraftCategoryItem(
        name: "Woodworking",
        description:
            "Cutting, shaping, and joining wood to make objects or furniture.",
        icon: Icons.forest_outlined,
      ),
      CraftCategoryItem(
        name: "Pottery & Ceramics",
        description: "Shaping wet clay and firing it in a kiln to harden it.",
        icon: Icons.emoji_food_beverage_outlined,
      ),
      CraftCategoryItem(
        name: "Sculpting",
        description:
            "Carving or molding materials like stone, clay, or metal into 3D art.",
        icon: Icons.architecture_outlined,
      ),
      CraftCategoryItem(
        name: "Leatherworking",
        description:
            "Cutting, tooling, and stitching leather into goods like bags or belts.",
        icon: Icons.work_outline,
      ),
    ],
  ),
  CraftCategoryGroup(
    title: "Paper and Print Crafts",
    previewVideoUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    items: [
      CraftCategoryItem(
        name: "Origami",
        description: "Folding paper into decorative shapes and figures.",
        icon: Icons.change_history_outlined,
      ),
      CraftCategoryItem(
        name: "Scrapbooking",
        description:
            "Designing and decorating photo albums with paper and embellishments.",
        icon: Icons.photo_album_outlined,
      ),
      CraftCategoryItem(
        name: "Calligraphy",
        description: "Creating artistic, decorative handwriting or lettering.",
        icon: Icons.edit_outlined,
      ),
      CraftCategoryItem(
        name: "Bookbinding",
        description:
            "Assembling pages into a protective cover by sewing or gluing.",
        icon: Icons.menu_book_outlined,
      ),
    ],
  ),
  CraftCategoryGroup(
    title: "Jewelry and Accessories",
    previewVideoUrl:
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    items: [
      CraftCategoryItem(
        name: "Beadwork",
        description: "Stringing or weaving beads together to make jewelry.",
        icon: Icons.circle_outlined,
      ),
      CraftCategoryItem(
        name: "Wire Wrapping",
        description:
            "Bending and twisting metal wire to hold stones or create shapes.",
        icon: Icons.cable_outlined,
      ),
      CraftCategoryItem(
        name: "Metalsmithing",
        description:
            "Melting, hammering, and soldering metal to forge jewelry.",
        icon: Icons.hardware_outlined,
      ),
    ],
  ),
];
