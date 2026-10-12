import 'package:digitalkhata/theme/app_theme.dart';
import 'package:flutter/material.dart';

/// Easy Khata logo tile.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      AppBrand.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '${AppBrand.name} logo',
    );
  }
}

/// Logo + "Easy Khata" wordmark.
class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.logoSize = 44,
    this.color = Colors.white,
    this.fontSize = 22,
  });

  final double logoSize;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandLogo(size: logoSize),
        const SizedBox(width: 12),
        Text(
          AppBrand.name,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
