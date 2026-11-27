import 'dart:io';

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// 统一封面控件：本地文件、网络图、缺省占位三种情况收敛到一处。
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.source,
    this.size = 48,
    this.radius = 8,
    this.fallbackSeed,
  });

  final String? source;
  final double size;
  final double radius;

  /// 无封面时用曲名首字生成占位，比统一图标更容易区分。
  final String? fallbackSeed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final String? src = source;
    if (src == null || src.isEmpty) return _fallback();
    if (src.startsWith('/')) {
      return Image.file(
        File(src),
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => _fallback(),
      );
    }
    if (src.startsWith('http')) {
      return Image.network(
        src,
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, _, _) => _fallback(),
        loadingBuilder: (BuildContext context, Widget child,
            ImageChunkEvent? progress) {
          if (progress == null) return child;
          return _fallback();
        },
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    final String? seed = fallbackSeed;
    final String letter = (seed == null || seed.trim().isEmpty)
        ? '♪'
        : seed.trim().substring(0, 1).toUpperCase();
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF3A332A), Color(0xFF211F1C)],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: AppColors.accent.withValues(alpha: 0.85),
          fontSize: size * 0.42,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
