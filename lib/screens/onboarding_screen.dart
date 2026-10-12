import 'package:digitalkhata/authentication/loginscreen.dart';
import 'package:digitalkhata/screens/mainscreen.dart';
import 'package:digitalkhata/theme/app_theme.dart';
import 'package:digitalkhata/widgets/brand.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const String completeKey = 'onboarding_complete_v1';

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pages = PageController();
  late final AnimationController _artController;
  int _page = 0;
  bool _saving = false;

  static const _content = <_OnboardingContent>[
    _OnboardingContent(
      eyebrow: 'YOUR BUSINESS, IN ONE PLACE',
      title: 'A clear khata for every customer',
      description:
          'Keep customer details, opening balances and payment history together. '
          'See at a glance who owes you and what has been settled.',
      icon: Icons.people_alt_rounded,
      accent: Color(0xFF81D9AA),
      chips: ['Customer list', 'Live balances'],
    ),
    _OnboardingContent(
      eyebrow: 'SIMPLE DAILY RECORDS',
      title: 'Record every GAVE and GOT',
      description:
          'Add an entry in a few taps. Your balance updates automatically, '
          'and you can review or correct an entry whenever needed.',
      icon: Icons.receipt_long_rounded,
      accent: Color(0xFFFFD17A),
      chips: ['Running balance', 'Editable history'],
    ),
    _OnboardingContent(
      eyebrow: 'BACKUP WITH CONFIDENCE',
      title: 'Your records, ready when you need them',
      description:
          'Back up to your private Google Drive or export a file to move your '
          'khata to another phone. Save or share a customer statement as PDF.',
      icon: Icons.shield_moon_rounded,
      accent: Color(0xFF9FC5FF),
      chips: ['Google Drive', 'Portable backup', 'PDF statements'],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _artController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pages.dispose();
    _artController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final preferences = await SharedPreferences.getInstance();
      final stored = await preferences.setBool(
        OnboardingScreen.completeKey,
        true,
      );
      if (!stored) {
        throw StateError('Could not save onboarding preference');
      }
      if (!mounted) return;

      final destination = FirebaseAuth.instance.currentUser == null
          ? const AuthScreen()
          : const Mainscreen();
      Navigator.of(context).pushReplacement(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => destination,
          transitionDuration: const Duration(milliseconds: 420),
          transitionsBuilder: (_, animation, _, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.025),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Saving onboarding state failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not save this step. Please try again.'),
          ),
        );
    }
  }

  void _next() {
    if (_page == _content.length - 1) {
      _finish();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 600;
            final headerLogoSize = compact ? 28.0 : 34.0;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(20, compact ? 2 : 8, 12, 0),
                  child: Row(
                    children: [
                      BrandLogo(size: headerLogoSize),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppBrand.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: compact ? 15 : 17,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _saving ? null : _finish,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: const Size(0, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _content.length,
                    onPageChanged: (index) => setState(() => _page = index),
                    itemBuilder: (context, index) => _OnboardingPage(
                      content: _content[index],
                      artController: _artController,
                      active: index == _page,
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    compact ? 2 : 8,
                    24,
                    compact ? 6 : 12,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: List.generate(
                              _content.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 260),
                                curve: Curves.easeOut,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                width: index == _page ? 26 : 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: index == _page
                                      ? AppColors.navy
                                      : const Color(0xFFD4D8DE),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 12),
                            Text(
                              '${_page + 1} of ${_content.length}',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving ? null : _next,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _saving
                                ? const SizedBox(
                                    key: ValueKey('saving'),
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Row(
                                    key: ValueKey('page-$_page'),
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        _page == _content.length - 1
                                            ? 'Get started'
                                            : 'Continue',
                                      ),
                                      const SizedBox(width: 10),
                                      Icon(
                                        _page == _content.length - 1
                                            ? Icons.arrow_forward_rounded
                                            : Icons.chevron_right_rounded,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _OnboardingContent {
  const _OnboardingContent({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.chips,
  });

  final String eyebrow;
  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final List<String> chips;
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.content,
    required this.artController,
    required this.active,
  });

  final _OnboardingContent content;
  final AnimationController artController;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 440;
        final horizontalPadding = constraints.maxWidth < 360 ? 16.0 : 24.0;
        final artHeight = (constraints.maxHeight * 0.43).clamp(112.0, 278.0);
        final artWidth = (constraints.maxWidth - horizontalPadding * 2).clamp(
          0.0,
          290.0,
        );

        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            4,
            horizontalPadding,
            8,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 12).clamp(
                0.0,
                double.infinity,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: artWidth,
                  height: artHeight,
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: artWidth,
                      height: 278,
                      child: _FeatureIllustration(
                        content: content,
                        controller: artController,
                        active: active,
                        width: artWidth,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 8 : 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Column(
                    key: ValueKey(content.title),
                    children: [
                      Text(
                        content.eyebrow,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.receivable,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.25,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        content.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontSize: 28,
                          height: 1.13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: Text(
                          content.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 14,
                            height: 1.6,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final chip in content.chips)
                            _FeatureChip(label: chip, accent: content.accent),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeatureIllustration extends StatelessWidget {
  const _FeatureIllustration({
    required this.content,
    required this.controller,
    required this.active,
    required this.width,
  });

  final _OnboardingContent content;
  final AnimationController controller;
  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final breath = active ? controller.value : 0.35;
        return Center(
          child: SizedBox(
            width: width,
            height: 278,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 0.94 + breath * 0.09,
                  child: Container(
                    width: 236,
                    height: 236,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: content.accent.withValues(alpha: 0.13),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, -3 * breath),
                  child: Container(
                    width: 216,
                    height: 248,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.navy.withValues(alpha: 0.12),
                          blurRadius: 35,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: content.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                content.icon,
                                color: AppColors.navy,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 9,
                                    width: 88,
                                    decoration: BoxDecoration(
                                      color: AppColors.ink,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Container(
                                    height: 6,
                                    width: 56,
                                    decoration: BoxDecoration(
                                      color: AppColors.border,
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.more_horiz_rounded,
                              color: AppColors.muted.withValues(alpha: 0.65),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Container(
                          height: 66,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F8FA),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      height: 6,
                                      width: 54,
                                      decoration: BoxDecoration(
                                        color: AppColors.muted.withValues(
                                          alpha: 0.35,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      height: 12,
                                      width: 76,
                                      decoration: BoxDecoration(
                                        color: content.accent.withValues(
                                          alpha: 0.75,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.trending_up_rounded,
                                color: AppColors.receivable,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        for (var i = 0; i < 2; i++) ...[
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: content.accent.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 6,
                                      width: i == 0 ? 86 : 66,
                                      decoration: BoxDecoration(
                                        color: AppColors.border,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Container(
                                      height: 5,
                                      width: i == 0 ? 54 : 42,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF0F2F5),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                height: 7,
                                width: 36,
                                decoration: BoxDecoration(
                                  color: i == 0
                                      ? AppColors.receivable.withValues(
                                          alpha: 0.4,
                                        )
                                      : AppColors.payable.withValues(
                                          alpha: 0.35,
                                        ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ],
                          ),
                          if (i == 0) const SizedBox(height: 10),
                        ],
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 35 + 5 * breath,
                  child: _FloatingBadge(
                    icon: content.icon,
                    color: content.accent,
                    label: 'Easy',
                  ),
                ),
                Positioned(
                  left: 2,
                  bottom: 27 - 6 * breath,
                  child: _FloatingBadge(
                    icon: Icons.check_rounded,
                    color: const Color(0xFF86D9A7),
                    label: 'Safe',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FloatingBadge extends StatelessWidget {
  const _FloatingBadge({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: AppColors.navy.withValues(alpha: 0.12),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.navy, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppColors.ink,
          ),
        ),
      ],
    ),
  );
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: accent.withValues(alpha: 0.5)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.navy,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
