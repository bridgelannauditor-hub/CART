import 'package:flutter/material.dart';

class CustomLogo extends StatelessWidget {
  const CustomLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/logos/2.png',
      width: 140,
      height: 140,
      fit: BoxFit.cover,
    );
  }
}
