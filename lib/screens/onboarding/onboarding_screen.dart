import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/onboarding_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/three_js_view.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingController controller;
  double _pageOffset = 0;

  @override
  void initState() {
    super.initState();
    controller = Get.find<OnboardingController>();
    _pageOffset = controller.index.value.toDouble();
    controller.pageController.addListener(_onPageScroll);
  }

  void _onPageScroll() {
    final page = controller.pageController.page;
    if (page == null || !mounted) return;
    setState(() => _pageOffset = page);
  }

  @override
  void dispose() {
    controller.pageController.removeListener(_onPageScroll);
    super.dispose();
  }

  /// Au repos : carte centrée.
  /// 0↔1 : parallax + skew + fondu
  /// 1↔2 : dissolve cinématique (profondeur, voile rouge, parallax)
  _SwipeFx _fxFor(double page) {
    final p = page.clamp(0.0, 2.0);
    final nearest = p.roundToDouble();
    final drift = p - nearest;
    final frac = p >= 2.0 - 1e-9 ? 0.0 : (p - p.floorToDouble());
    final pulse = math.sin(frac * math.pi);
    final firstLeg = p <= 1.0;

    if (firstLeg) {
      return _SwipeFx(
        mapScale: 1.0,
        mapDx: -drift * 130,
        mapDy: 0,
        mapRotate: 0,
        mapSkewX: drift.sign * pulse * 0.14,
        mapOpacity: (1.0 - pulse * 0.55).clamp(0.3, 1.0),
        veilOpacity: pulse * 0.28,
        accentVeil: 0,
        copyDxFactor: -80,
        copyDy: pulse * 22,
        copyScale: 1.0,
        copyFadeExtra: pulse * 0.32,
        scaleAlign: Alignment.center,
      );
    }

    // 2 → 3 : profondeur + fondu teinté + parallax (sans bascule brutale)
    final depth = Curves.easeInOut.transform(pulse);
    return _SwipeFx(
      mapScale: 1.0 + depth * 0.12,
      mapDx: -drift * 78,
      mapDy: -depth * 16 + math.sin(frac * math.pi * 2) * 6 * pulse,
      mapRotate: 0,
      mapSkewX: drift.sign * depth * 0.045,
      mapOpacity: (1.0 - depth * 0.4).clamp(0.42, 1.0),
      veilOpacity: depth * 0.22,
      accentVeil: depth * 0.2,
      copyDxFactor: -58,
      copyDy: 32 * depth,
      copyScale: 0.9 + (1.0 - depth) * 0.1,
      copyFadeExtra: depth * 0.34,
      scaleAlign: const Alignment(0, 0.2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final themeController = Get.find<ThemeController>();

    return Obx(() {
      final isDark = themeController.isDarkMode;
      final page = controller.currentPage;
      final isLast = controller.isLast;
      final index = controller.index.value;
      final ink = isDark ? AppColors.white : AppColors.black;
      final muted = isDark ? AppColors.whiteMuted : AppColors.gray;
      final isCity = page.visual == OnboardingVisual.city;
      final isCivic = page.visual == OnboardingVisual.civic;
      final mapFlex = (isCity || isCivic) ? 7 : 6;
      final copyFlex = (isCity || isCivic) ? 3 : 4;
      final fx = _fxFor(_pageOffset);

      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: fx.mapOpacity,
              child: Transform.translate(
                offset: Offset(fx.mapDx * 0.25, fx.mapDy * 0.35),
                child: _OnboardingBackdrop(
                  isDark: isDark,
                  visual: page.visual,
                  pageOffset: _pageOffset,
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _TopBar(
                    isDark: isDark,
                    isLast: isLast,
                    onToggleTheme: themeController.toggleTheme,
                    onSkip: controller.finish,
                  ),
                  Expanded(
                    flex: mapFlex,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragEnd: (details) {
                        final v = details.primaryVelocity ?? 0;
                        if (v < -220) {
                          controller.next();
                        } else if (v > 220 && index > 0) {
                          controller.pageController.previousPage(
                            duration: Duration(
                              milliseconds: index >= 2 ? 640 : 500,
                            ),
                            curve: Curves.easeInOutCubic,
                          );
                        }
                      },
                      child: ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Opacity(
                              opacity: fx.mapOpacity,
                              child: Transform.translate(
                                offset: Offset(fx.mapDx, fx.mapDy),
                                child: Transform.scale(
                                  alignment: fx.scaleAlign,
                                  scale: fx.mapScale,
                                  child: Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..setEntry(3, 2, 0.0012 * fx.accentVeil)
                                      ..rotateZ(fx.mapRotate)
                                      ..setEntry(0, 1, fx.mapSkewX),
                                    child: const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      child: IgnorePointer(
                                        child: ThreeJsView(scene: 'welcome'),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (fx.veilOpacity > 0.01 || fx.accentVeil > 0.01)
                              IgnorePointer(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      center: Alignment(
                                        (_pageOffset - index).clamp(-1.0, 1.0),
                                        -0.15,
                                      ),
                                      radius: 1.15,
                                      colors: [
                                        AppColors.red.withValues(
                                          alpha: fx.accentVeil,
                                        ),
                                        (isDark
                                                ? AppColors.black
                                                : AppColors.white)
                                            .withValues(alpha: fx.veilOpacity),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.0, 0.45, 1.0],
                                    ),
                                  ),
                                ),
                              ),
                            if (isCity)
                              Transform.translate(
                                offset: Offset(
                                  -(_pageOffset - 1) * 40,
                                  fx.mapDy * 0.4,
                                ),
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      0,
                                      24,
                                      8,
                                    ),
                                    child: Opacity(
                                      opacity: ((1 - (_pageOffset - 1).abs()) *
                                              fx.mapOpacity)
                                          .clamp(0.0, 1.0),
                                      child: Text(
                                        'Commune de Foumbot',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (isCivic)
                              Transform.translate(
                                offset: Offset(
                                  (_pageOffset - 2) * 48,
                                  fx.mapDy * 0.6 - fx.accentVeil * 20,
                                ),
                                child: Transform.scale(
                                  scale: 0.92 + fx.mapOpacity * 0.08,
                                  child: Opacity(
                                    opacity: ((1 - (_pageOffset - 2).abs()) *
                                            fx.mapOpacity)
                                        .clamp(0.0, 1.0),
                                    child: const _CivicOverlay(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: copyFlex,
                    child: PageView.builder(
                      controller: controller.pageController,
                      itemCount: OnboardingController.pages.length,
                      onPageChanged: controller.onPageChanged,
                      physics: const BouncingScrollPhysics(),
                      itemBuilder: (context, i) {
                        final p = OnboardingController.pages[i];
                        final delta = _pageOffset - i;
                        final baseOpacity =
                            (1 - delta.abs() * 0.95).clamp(0.0, 1.0);
                        // Chaque page a sa propre entrée texte
                        final textFx = switch (i) {
                          0 => (
                              dx: delta * -64.0,
                              dy: delta.abs() * 14.0,
                              sc: 1.0,
                            ),
                          1 => (
                              dx: delta * fx.copyDxFactor,
                              dy: fx.copyDy,
                              sc: 1.0,
                            ),
                          _ => (
                              dx: delta * -58.0,
                              dy: 40.0 * delta.abs(),
                              sc: 0.88 +
                                  (1 - delta.abs()).clamp(0.0, 1.0) * 0.12,
                            ),
                        };
                        return Transform.translate(
                          offset: Offset(textFx.dx, textFx.dy),
                          child: Transform.scale(
                            scale: textFx.sc,
                            child: Opacity(
                              opacity: (baseOpacity - fx.copyFadeExtra)
                                  .clamp(0.0, 1.0),
                              child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(28, 4, 28, 8),
                                child: _PageCopy(
                                  page: p,
                                  ink: ink,
                                  muted: muted,
                                  isDark: isDark,
                                  textTheme: textTheme,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
                    child: Row(
                      children: [
                        for (var i = 0;
                            i < OnboardingController.pages.length;
                            i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            margin: const EdgeInsets.only(right: 8),
                            height: 4,
                            width: i == index ? 28 : 10,
                            decoration: BoxDecoration(
                              color: i == index
                                  ? AppColors.red
                                  : ink.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        const Spacer(),
                        _CtaButton(
                          label: isLast ? 'Commencer' : 'Continuer',
                          onPressed: controller.next,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _SwipeFx {
  const _SwipeFx({
    required this.mapScale,
    required this.mapDx,
    required this.mapDy,
    required this.mapRotate,
    required this.mapSkewX,
    required this.mapOpacity,
    required this.veilOpacity,
    required this.accentVeil,
    required this.copyDxFactor,
    required this.copyDy,
    required this.copyScale,
    required this.copyFadeExtra,
    required this.scaleAlign,
  });

  final double mapScale;
  final double mapDx;
  final double mapDy;
  final double mapRotate;
  final double mapSkewX;
  final double mapOpacity;
  final double veilOpacity;
  final double accentVeil;
  final double copyDxFactor;
  final double copyDy;
  final double copyScale;
  final double copyFadeExtra;
  final Alignment scaleAlign;
}

class _PageCopy extends StatelessWidget {
  const _PageCopy({
    required this.page,
    required this.ink,
    required this.muted,
    required this.isDark,
    required this.textTheme,
  });

  final OnboardingPageData page;
  final Color ink;
  final Color muted;
  final bool isDark;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.eyebrow.toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  page.title,
                  style: textTheme.headlineMedium?.copyWith(
                    color: ink,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  page.subtitle,
                  style: textTheme.bodyMedium?.copyWith(
                    color: muted,
                    height: 1.4,
                  ),
                ),
                if (page.highlights.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (var i = 0; i < page.highlights.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _HighlightRow(
                      icon: page.highlights[i].icon,
                      label: page.highlights[i].label,
                      isDark: isDark,
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingBackdrop extends StatelessWidget {
  const _OnboardingBackdrop({
    required this.isDark,
    required this.visual,
    this.pageOffset = 0,
  });

  final bool isDark;
  final OnboardingVisual visual;
  final double pageOffset;

  @override
  Widget build(BuildContext context) {
    final base = isDark
        ? const [
            AppColors.black,
            AppColors.blackSoft,
            Color(0xFF120808),
          ]
        : const [
            AppColors.white,
            AppColors.whiteSoft,
            Color(0xFFFFF5F5),
          ];
    final shift = pageOffset * 0.08;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: base,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (visual == OnboardingVisual.civic) ...[
            Align(
              alignment: Alignment(-1.1 + shift, -0.55),
              child: _GlowOrb(
                size: 280,
                color: AppColors.blue.withValues(alpha: isDark ? 0.22 : 0.14),
              ),
            ),
            Align(
              alignment: Alignment(1.15 + shift, -0.2),
              child: _GlowOrb(
                size: 240,
                color: AppColors.red.withValues(alpha: isDark ? 0.18 : 0.10),
              ),
            ),
          ],
          if (visual == OnboardingVisual.city) ...[
            Align(
              alignment: Alignment(0.9 + shift, -0.4),
              child: _GlowOrb(
                size: 220,
                color: AppColors.blue.withValues(alpha: isDark ? 0.16 : 0.10),
              ),
            ),
            Align(
              alignment: Alignment(-0.95 + shift, 0.1),
              child: _GlowOrb(
                size: 180,
                color: AppColors.red.withValues(alpha: isDark ? 0.12 : 0.07),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isDark,
    required this.isLast,
    required this.onToggleTheme,
    required this.onSkip,
  });

  final bool isDark;
  final bool isLast;
  final VoidCallback onToggleTheme;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Text(
            'Foumbot',
            style: textTheme.headlineMedium?.copyWith(
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Thème',
            onPressed: onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: AppColors.red,
            ),
          ),
          if (!isLast)
            TextButton(
              onPressed: onSkip,
              child: Text(
                'Passer',
                style: textTheme.bodyLarge?.copyWith(
                  color: isDark ? AppColors.whiteMuted : AppColors.gray,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CivicOverlay extends StatelessWidget {
  const _CivicOverlay();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(
          top: 16,
          right: 28,
          child: _OrbitChip(icon: Icons.campaign_outlined),
        ),
        Positioned(
          left: 24,
          bottom: 24,
          child: _OrbitChip(icon: Icons.forum_outlined),
        ),
        Positioned(
          right: 28,
          bottom: 28,
          child: _OrbitChip(icon: Icons.lightbulb_outline),
        ),
      ],
    );
  }
}

class _OrbitChip extends StatelessWidget {
  const _OrbitChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? AppColors.blackElevated : AppColors.white,
        border: Border.all(
          color: AppColors.blue.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, size: 22, color: AppColors.blue),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.blue),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.white : AppColors.black,
            ),
          ),
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.red,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.white,
                ),
          ),
        ),
      ),
    );
  }
}
