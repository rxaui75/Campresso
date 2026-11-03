import 'package:flutter/material.dart';
import 'package:campresso/features/common/auth/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  static const Color _bg = Color(0xFFCFE7E6);
  static const Color _primary = Color(0xFF0E6F73);

  late final List<_OnboardModel> _pages;
  bool _built = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_built) return;

    final t = AppLocalizations.of(context)!;

    _pages = [
      _OnboardModel(
        image: 'assets/images/onboarding/1.png',
        title: t.onbTitle1,
        description: t.onbDesc1,
        caption: t.onbCaption1,
      ),
      _OnboardModel(
        image: 'assets/images/onboarding/2.png',
        title: t.onbTitle2,
        description: t.onbDesc2,
        caption: t.onbCaption2,
      ),
      _OnboardModel(
        image: 'assets/images/onboarding/3.png',
        title: t.onbTitle3,
        description: t.onbDesc3,
        caption: t.onbCaption3,
      ),
    ];

    _built = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                  offset: const Offset(0, 6),
                                  color: Colors.black.withOpacity(0.12),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  p.image,
                                  height: 90,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  p.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: _primary,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  p.description,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.3,
                                    color: Colors.black.withOpacity(0.65),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            p.caption,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Colors.black.withOpacity(0.55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 10),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                    (i) => _Dot(
                  isActive: i == _index,
                  activeColor: Colors.black.withOpacity(0.65),
                  inactiveColor: Colors.black.withOpacity(0.20),
                ),
              ),
            ),

            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _index == _pages.length - 1
                    ? ElevatedButton(
                  key: const ValueKey('start'),
                  onPressed: _finish,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    t.getStarted,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
                    : const SizedBox(height: 44),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================== MODELS & WIDGETS ==================

class _OnboardModel {
  final String image;
  final String title;
  final String description;
  final String caption;

  const _OnboardModel({
    required this.image,
    required this.title,
    required this.description,
    required this.caption,
  });
}

class _Dot extends StatelessWidget {
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;

  const _Dot({
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 5),
      height: 8,
      width: isActive ? 26 : 8,
      decoration: BoxDecoration(
        color: isActive ? activeColor : inactiveColor,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}