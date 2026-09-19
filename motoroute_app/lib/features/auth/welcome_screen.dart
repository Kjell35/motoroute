import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:motoroute_app/core/theme/app_colors.dart';
import 'package:motoroute_app/core/theme/app_spacing.dart';
import 'package:motoroute_app/core/theme/app_typography.dart';
import 'package:motoroute_app/features/auth/auth_providers.dart';

/// Willkommens-Screen: Begruessung bei jedem App-Start (nach dem
/// Splash), Anmeldung/Registrierung mit E-Mail + Passwort. Bei JEDER
/// erfolgreichen Anmeldung fragt der Dialog "Gerät merken?" - nur
/// bei Ja bleibt die Sitzung über App-Neustarts bestehen.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isRegister = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.length < 6) {
      setState(() => _error = 'E-Mail eingeben und Passwort (min. 6 Zeichen)');
      return;
    }

    // 1) Anmelden/Registrieren (Sitzung lebt erst mal nur In-Memory).
    try {
      await ref.read(authControllerProvider.notifier).authenticate(
            email: email,
            password: password,
            remember: false,
            register: _isRegister,
            displayName: _nameController.text.trim(),
          );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return;
    }

    // 2) Geraete-Merken-Frage - bei JEDER Anmeldung neu gestellt.
    if (!mounted) return;
    final remember = await _askRememberDevice();
    if (!mounted) return;

    // 3) Bei "Ja" die LAUFENDE Sitzung persistieren (kein zweiter
    //    Login-Call): danach überlebt sie App-Neustarts. Bei "Nein"
    //    bleibt alles In-Memory und endet mit dem Prozess.
    if (remember) {
      await ref.read(authControllerProvider.notifier).persistCurrentSession();
    }

    if (!mounted) return;
    final user = ref.read(authControllerProvider).user;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Willkommen, ${user?.name ?? 'Rider'}! 🏍️',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.accentPrimaryDark,
      ),
    );
    Navigator.of(context).pushReplacementNamed('/home');
  }

  Future<bool> _askRememberDevice() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgSurfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.phone_iphone, color: AppColors.accentPrimaryDark),
            const SizedBox(width: AppSpacing.sm),
            Text('Gerät merken?', style: AppTypography.title),
          ],
        ),
        content: Text(
          'Wenn du das Gerät merkst, bleibst du nach einem App-Neustart '
          'angemeldet. Andernfalls musst du dich beim nächsten Start '
          'erneut anmelden.\n\nWir fragen dich bei jeder Anmeldung neu.',
          style: AppTypography.caption,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Nur diese Sitzung',
                style: TextStyle(color: AppColors.textSecondaryDark)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentPrimaryDark,
              foregroundColor: AppColors.textPrimaryDark,
            ),
            child: const Text('Gerät merken'),
          ),
        ],
      ),
    ).then((value) => value ?? false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.bgBaseDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Begruessungs-Emblem (wie Splash, aber interaktiv).
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentPrimaryDark.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.accentPrimaryDark.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.two_wheeler,
                      size: 48, color: AppColors.accentPrimaryDark),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _isRegister ? 'Willkommen an Bord!' : 'Willkommen zurück!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryDark,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _isRegister
                      ? 'Erstelle dein MotoRoute-Konto'
                      : 'Schön, dass du wieder fährst.',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption,
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_isRegister) ...[
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration('Dein Name (optional)'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: _inputDecoration('E-Mail'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: _inputDecoration('Passwort').copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppColors.textSecondaryDark,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.statusDanger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.statusDanger.withValues(alpha: 0.4)),
                    ),
                    child: Text(_error!,
                        style: const TextStyle(color: AppColors.statusDanger)),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  height: AppSpacing.touchTargetPlanning,
                  child: FilledButton(
                    onPressed: auth.isBusy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentPrimaryDark,
                      foregroundColor: AppColors.textPrimaryDark,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: auth.isBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isRegister ? 'Konto erstellen' : 'Anmelden',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: auth.isBusy
                      ? null
                      : () => setState(() {
                          _isRegister = !_isRegister;
                          _error = null;
                        }),
                  child: Text(
                    _isRegister
                        ? 'Ich habe schon ein Konto - Anmelden'
                        : 'Neu hier? Konto erstellen',
                    style: const TextStyle(color: AppColors.accentSecondary),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed('/home'),
                  child: const Text(
                    'Erstmal ohne Konto ansehen',
                    style: TextStyle(color: AppColors.textMutedDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textSecondaryDark),
        filled: true,
        fillColor: AppColors.bgSurfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderHairlineDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.borderHairlineDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.accentPrimaryDark),
        ),
      );
}
