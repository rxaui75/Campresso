import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:campresso/main.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class LanguagesPage extends StatefulWidget {
  const LanguagesPage({super.key});

  @override
  State<LanguagesPage> createState() => _LanguagesPageState();
}

class _LanguagesPageState extends State<LanguagesPage> {
  static const _primary = Color(0xFF0E6F73);

  String _selected = 'en';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('app_lang') ?? 'en';
    if (!mounted) return;
    setState(() => _selected = v);
  }

  Future<void> _save(String lang) async {
    await MyApp.of(context)!.setLocale(lang);
    if (!mounted) return;

    setState(() => _selected = lang);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, lang);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
        title: Text(t.languages, style: const TextStyle(fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.suggested,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),

            _LangTile(
              title: t.arabicSA,
              selected: _selected == 'ar',
              onTap: () => _save('ar'),
              activeColor: _primary,
            ),
            const SizedBox(height: 10),
            _LangTile(
              title: t.englishUS,
              selected: _selected == 'en',
              onTap: () => _save('en'),
              activeColor: _primary,
            ),
          ],
        ),
      ),
    );
  }
}

class _LangTile extends StatelessWidget {
  final String title;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _LangTile({
    required this.title,
    required this.selected,
    required this.onTap,
    this.activeColor = const Color(0xFF0E6F73),
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 14.5)),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? activeColor : Colors.black.withOpacity(0.25),
                width: 3,
              ),
            ),
            child: selected
                ? Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: activeColor,
                ),
              ),
            )
                : null,
          )
        ],
      ),
    );
  }
}
