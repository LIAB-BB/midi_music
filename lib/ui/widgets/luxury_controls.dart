import 'package:flutter/cupertino.dart';

import '../theme/luxury_theme.dart';

class LuxuryActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool primary;

  const LuxuryActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = primary
        ? BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFE8CF99), Color(0xFFC49A57)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: LuxuryPalette.gold.withValues(alpha: 0.22),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          )
        : BoxDecoration(
            color: CupertinoColors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: LuxuryPalette.divider),
          );
    final foreground = primary
        ? CupertinoColors.black
        : LuxuryPalette.textPrimary;

    return DecoratedBox(
      decoration: decoration,
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: primary ? 18 : 16,
        ),
        borderRadius: BorderRadius.circular(20),
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: primary ? 18 : 16, color: foreground),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: primary ? 15 : 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LuxuryMetricTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? accent;
  final double? width;

  const LuxuryMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.accent,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = accent ?? LuxuryPalette.goldBright;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: accent == null
            ? CupertinoColors.white.withValues(alpha: 0.03)
            : effectiveAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent == null
              ? LuxuryPalette.divider
              : effectiveAccent.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: LuxuryPalette.textSubtle,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: effectiveAccent,
            ),
          ),
        ],
      ),
    );
  }
}
