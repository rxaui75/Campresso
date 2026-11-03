import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '/flutter_gen/gen_l10n/app_localizations.dart';

class CardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final digitsOnly = newValue.text.replaceAll(RegExp(r'\D'), '');

    final buffer = StringBuffer();
    for (int i = 0; i < digitsOnly.length; i++) {
      buffer.write(digitsOnly[i]);
      final isEndOfBlock = (i + 1) % 4 == 0;
      final isNotLast = i != digitsOnly.length - 1;
      if (isEndOfBlock && isNotLast) buffer.write(' ');
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AddCardPage extends StatefulWidget {
  const AddCardPage({super.key});

  @override
  State<AddCardPage> createState() => _AddCardPageState();
}

class _AddCardPageState extends State<AddCardPage> {
  static const _primary = Color(0xFF0E6F73);

  final _formKey = GlobalKey<FormState>();

  final _holder = TextEditingController();
  final _number = TextEditingController();
  final _valid = TextEditingController(); // MM/YY
  final _cvv = TextEditingController();

  int _selectedMonth = 12;
  int _selectedYear = DateTime.now().year;

  bool _loading = false;

  @override
  void dispose() {
    _holder.dispose();
    _number.dispose();
    _valid.dispose();
    _cvv.dispose();
    super.dispose();
  }

  String _onlyDigits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  String _detectBrand(String digits) {
    if (digits.startsWith('5')) return 'mastercard';
    return 'visa';
  }

  Future<void> _save() async {
    final t = AppLocalizations.of(context)!;

    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.noUserSignedIn)),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final digits = _onlyDigits(_number.text);
      final last4 =
      digits.length >= 4 ? digits.substring(digits.length - 4) : digits;
      final brand = _detectBrand(digits);

      final parts = _valid.text.trim().split('/');
      final mm = int.tryParse(parts.first.trim()) ?? 0;
      final yy = int.tryParse(parts.length > 1 ? parts[1].trim() : '') ?? 0;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('cards')
          .add({
        'brand': brand,
        'cardHolder': _holder.text.trim().toUpperCase(),
        'last4': last4,
        'expMonth': mm,
        'expYear': 2000 + yy,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${t.failedToSaveCard}: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _dec() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFD6E9EA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
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
        title: Text(
          t.paymentMethod,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
        children: [
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.circle, color: Colors.red, size: 20),
              const Icon(Icons.circle, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Container(width: 1, height: 18, color: Colors.black12),
              const SizedBox(width: 12),
              const Text(
                'VISA',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Colors.blue,
                  fontSize: 18,
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.cardHolder, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _holder,
                  textCapitalization: TextCapitalization.characters,
                  decoration: _dec(),
                  validator: (v) =>
                  (v ?? '').trim().isEmpty ? t.enterCardHolderName : null,
                ),

                const SizedBox(height: 14),
                Text(t.cardNumber, style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _number,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(16),
                    CardNumberInputFormatter(),
                  ],
                  decoration: _dec(),
                  validator: (v) {
                    final digits = _onlyDigits(v ?? '');
                    if (digits.isEmpty) return t.enterCardNumber;
                    if (digits.length < 12) return t.cardNumberTooShort;
                    return null;
                  },
                ),

                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.valid, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: _openExpiryPicker,
                            child: AbsorbPointer(
                              child: TextFormField(
                                controller: _valid,
                                decoration: _dec().copyWith(hintText: 'MM/YY'),
                                validator: (v) {
                                  if ((v ?? '').trim().isEmpty) return t.requiredField;
                                  return null;
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.cvv, style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _cvv,
                            keyboardType: TextInputType.number,
                            obscureText: true,
                            decoration: _dec(),
                            validator: (v) {
                              final digits = _onlyDigits(v ?? '');
                              if (digits.isEmpty) return t.requiredField;
                              if (digits.length < 3) return t.tooShort;
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                Center(
                  child: SizedBox(
                    width: 220,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _loading
                          ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                          : Text(
                        t.save,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openExpiryPicker() {
    final t = AppLocalizations.of(context)!;

    final now = DateTime.now();
    int tempMonth = _selectedMonth;
    int tempYear = _selectedYear == 0 ? now.year : _selectedYear;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return SizedBox(
          height: 320,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t.cancel),
                    ),
                    Text(
                      t.selectExpiry,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedMonth = tempMonth;
                          _selectedYear = tempYear;
                          _valid.text =
                          '${_selectedMonth.toString().padLeft(2, '0')}/${(_selectedYear % 100).toString().padLeft(2, '0')}';
                        });
                        Navigator.pop(context);
                      },
                      child: Text(t.done),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: tempMonth - 1,
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) => tempMonth = i + 1,
                        children: List.generate(12, (i) {
                          final m = i + 1;
                          return Center(
                            child: Text(m.toString().padLeft(2, '0')),
                          );
                        }),
                      ),
                    ),
                    Expanded(
                      child: CupertinoPicker(
                        scrollController: FixedExtentScrollController(
                          initialItem: (tempYear - now.year).clamp(0, 14),
                        ),
                        itemExtent: 36,
                        onSelectedItemChanged: (i) => tempYear = now.year + i,
                        children: List.generate(15, (i) {
                          final y = now.year + i;
                          return Center(child: Text(y.toString()));
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
