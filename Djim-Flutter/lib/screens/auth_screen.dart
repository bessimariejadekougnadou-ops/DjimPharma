import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/animated_medicine_capsule.dart';
import 'home_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _authService = AuthService();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _rememberMe = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isLogin && _passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Les mots de passe ne correspondent pas.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      if (_isLogin) {
        await _authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: const Color(0xFF14532D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connexion réussie ! Bienvenue sur DjimPharma 🇹🇬',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 1400),
          ),
        );

        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      } else {
        await _authService.register(
          firstName: _firstNameController.text,
          lastName: _lastNameController.text,
          email: _emailController.text,
          password: _passwordController.text,
          phone: _phoneController.text,
        );

        if (!mounted) return;
        setState(() {
          _isLogin = true;
          _passwordController.clear();
          _confirmPasswordController.clear();
          _successMessage = 'Compte créé avec succès ! Connectez-vous maintenant.';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            backgroundColor: const Color(0xFF14532D),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Compte créé avec succès ! 🎉',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 2000),
          ),
        );
      }
    } on AuthException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
        _showErrorSnackBar(error.message);
      }
    } on TimeoutException {
      if (mounted) {
        const msg = 'Le serveur ne répond pas. Vérifiez que Django est lancé sur votre PC.';
        setState(() => _errorMessage = msg);
        _showErrorSnackBar(msg);
      }
    } catch (_) {
      if (mounted) {
        const msg = 'Connexion impossible. Vérifiez l\'adresse du serveur et le réseau.';
        setState(() => _errorMessage = msg);
        _showErrorSnackBar(msg);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: const Color(0xFFB42318),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _motDePasseOublie() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Row(
          children: [
            Icon(Icons.lock_reset_rounded, color: Color(0xFF14532D)),
            SizedBox(width: 8),
            Text("Mot de passe oublié", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
          ],
        ),
        content: const Text(
          "Veuillez entrer votre adresse email. Un lien de réinitialisation sécurisé vous sera envoyé.",
          style: TextStyle(fontSize: 13, color: Color(0xFF334155), height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Fermer"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Email de réinitialisation envoyé si le compte existe."),
                  backgroundColor: Color(0xFF14532D),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF14532D),
              foregroundColor: Colors.white,
            ),
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label est obligatoire.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── FOND COLORÉ AVEC PATTERN BOTANIQUE & MÉDICAL (STYLE VÉGIGO) ───
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF86EFAC), // Vert menthe frais et lumineux
                    Color(0xFFA7F3D0),
                    Color(0xFF6EE7B7),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: CustomPaint(
                painter: _MedicalBotanicalBackgroundPainter(),
              ),
            ),
          ),

          // ── CONTENU PRINCIPAL DÉFILANT ──────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── 1. COMPRIMÉS 3D FLOTTANTS (THEME DJIMPHARMA ÉMERAUDE) ────
                    AnimatedMedicineCapsule(
                      isLogin: _isLogin,
                      theme: MedicineColorTheme.djimPharmaEmerald,
                      size: 82,
                    ),

                    const SizedBox(height: 14),

                    // ── 2. CARTE FLOTTANTE DOUCE (STYLE EXACT DU MOCKUP) ─────────
                    Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F7ED), // Teinte menthe très pâle et douce
                        borderRadius: BorderRadius.circular(34),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF064E3B).withValues(alpha: 0.16),
                            blurRadius: 26,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Titre principal
                            Text(
                              _isLogin ? "Connexion" : "Inscription",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF14532D),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isLogin
                                  ? "Votre santé simplifiée au Togo."
                                  : "Rejoignez DjimPharma gratuitement.",
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF4B5563),
                              ),
                            ),

                            const SizedBox(height: 22),

                            // Champs d'inscription
                            if (!_isLogin) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInputField(
                                      controller: _firstNameController,
                                      label: "Prénom",
                                      hint: "Koffi",
                                      icon: Icons.person_outline_rounded,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _buildInputField(
                                      controller: _lastNameController,
                                      label: "Nom",
                                      hint: "Mensah",
                                      icon: Icons.badge_outlined,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Email
                            _buildInputField(
                              controller: _emailController,
                              label: "Email",
                              hint: "exemple@gmail.com",
                              icon: Icons.mail_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                            ),

                            const SizedBox(height: 12),

                            // Téléphone optionnel si inscription
                            if (!_isLogin) ...[
                              _buildInputField(
                                controller: _phoneController,
                                label: "Téléphone (optionnel)",
                                hint: "+228 90 00 00 00",
                                icon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                required: false,
                              ),
                              const SizedBox(height: 12),
                            ],

                            // Mot de passe
                            _buildInputField(
                              controller: _passwordController,
                              label: "Mot de passe",
                              hint: "••••••••••••",
                              icon: Icons.lock_outline_rounded,
                              isPassword: true,
                              obscureText: _obscurePassword,
                              onToggleVisibility: () {
                                setState(() => _obscurePassword = !_obscurePassword);
                              },
                            ),

                            // Confirmer mot de passe si inscription
                            if (!_isLogin) ...[
                              const SizedBox(height: 12),
                              _buildInputField(
                                controller: _confirmPasswordController,
                                label: "Confirmer le mot de passe",
                                hint: "••••••••••••",
                                icon: Icons.lock_outline_rounded,
                                isPassword: true,
                                obscureText: _obscureConfirmPassword,
                                onToggleVisibility: () {
                                  setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
                                },
                              ),
                            ],

                            // Ligne Se souvenir de moi & Mot de passe oublié (en mode Connexion)
                            if (_isLogin) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: Checkbox(
                                            value: _rememberMe,
                                            onChanged: (val) => setState(() => _rememberMe = val ?? true),
                                            activeColor: const Color(0xFF14532D),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFF14532D),
                                              width: 1.2,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Text(
                                          "Se souvenir de moi",
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _motDePasseOublie,
                                    child: const Text(
                                      "Mot de passe oublié ?",
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF14532D),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Message d'erreur
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFFF87171)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: const TextStyle(
                                          color: Color(0xFFB91C1C),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Message de succès
                            if (_successMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF4ADE80)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF16A34A), size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _successMessage!,
                                        style: const TextStyle(
                                          color: Color(0xFF15803D),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 18),

                            // ── 3. BOUTON PRINCIPAL VERT FONCÉ ───────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _submit,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF14532D), // Vert profond exact
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : Text(
                                        _isLogin ? "Se connecter" : "S'inscrire",
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                              ),
                            ),

                            const SizedBox(height: 12),

                            // ── 4. SÉPARATEUR "- OU -" ───────────────────────────
                            Row(
                              children: [
                                Expanded(child: Divider(color: const Color(0xFF14532D).withValues(alpha: 0.20), thickness: 0.8)),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    "- OU -",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF14532D),
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: const Color(0xFF14532D).withValues(alpha: 0.20), thickness: 0.8)),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // ── 5. BOUTON GOOGLE CONTOUR VERT ─────────────────────
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton(
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Connexion Google disponible prochainement. Utilisez votre email."),
                                      backgroundColor: Color(0xFF14532D),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF14532D),
                                  side: const BorderSide(color: Color(0xFF14532D), width: 1.2),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildGoogleIcon(),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isLogin ? "Continuer avec Google" : "S'inscrire avec Google",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF14532D),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // ── 6. LIEN DE BASCULE EN BAS DE CARTE ────────────────
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _errorMessage = null;
                                  _successMessage = null;
                                });
                              },
                              child: RichText(
                                textAlign: TextAlign.center,
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF475569),
                                  ),
                                  children: [
                                    TextSpan(
                                      text: _isLogin
                                          ? "Vous n'avez pas de compte ? "
                                          : "Vous avez déjà un compte ? ",
                                    ),
                                    TextSpan(
                                      text: _isLogin ? "S'inscrire ici !" : "Se connecter ici !",
                                      style: const TextStyle(
                                        color: Color(0xFF14532D),
                                        fontWeight: FontWeight.w900,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // ── 7. LOGO DE MARQUE EN BAS DE L'ÉCRAN (EXACTEMENT COMME VEGIGO) ──
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: Color(0xFF14532D),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.eco_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          "DjimPharma",
                          style: TextStyle(
                            fontFamily: 'serif',
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Color(0xFF14532D),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Icône Google "G" verte fidèle au design
  Widget _buildGoogleIcon() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF14532D), width: 1.4),
      ),
      child: const Center(
        child: Text(
          "G",
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: Color(0xFF14532D),
          ),
        ),
      ),
    );
  }

  /// Champ de formulaire avec label externe et champ blanc arrondi
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    bool required = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD1FAE5),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF14532D).withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
            cursorColor: const Color(0xFF14532D),
            validator: required ? (value) => _required(value, label) : null,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF14532D), size: 19),
              suffixIcon: isPassword
                  ? IconButton(
                      icon: Icon(
                        obscureText
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF64748B),
                        size: 18,
                      ),
                      onPressed: onToggleVisibility,
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ),
      ],
    );
  }
}

/// Peintre artistique pour le motif botanique et santé en arrière-plan (Style Vegigo)
class _MedicalBotanicalBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    // 1. Feuilles et motifs organiques (haut-gauche)
    _drawLeaf(canvas, strokePaint, const Offset(30, 40), 28, -math.pi / 4);
    _drawLeaf(canvas, strokePaint, const Offset(55, 60), 20, math.pi / 6);
    _drawPill(canvas, strokePaint, fillPaint, const Offset(90, 30), 22, 10, math.pi / 5);

    // 2. Comprimés et motifs (haut-droite)
    _drawCapsule(canvas, strokePaint, fillPaint, Offset(size.width - 50, 45), 32, 14, -math.pi / 6);
    _drawLeaf(canvas, strokePaint, Offset(size.width - 80, 75), 24, math.pi / 3);
    _drawCross(canvas, strokePaint, Offset(size.width - 30, 110), 12);

    // 3. Motifs latéraux (milieu-gauche)
    _drawCapsule(canvas, strokePaint, fillPaint, const Offset(20, 240), 30, 13, math.pi / 4);
    _drawLeaf(canvas, strokePaint, const Offset(40, 290), 26, -math.pi / 3);
    _drawPill(canvas, strokePaint, fillPaint, const Offset(15, 360), 20, 10, 0);

    // 4. Motifs latéraux (milieu-droite)
    _drawPill(canvas, strokePaint, fillPaint, Offset(size.width - 25, 230), 24, 11, -math.pi / 4);
    _drawCapsule(canvas, strokePaint, fillPaint, Offset(size.width - 35, 310), 32, 13, math.pi / 6);
    _drawLeaf(canvas, strokePaint, Offset(size.width - 20, 390), 25, -math.pi / 5);

    // 5. Motifs en bas (bas-gauche & bas-droite)
    _drawLeaf(canvas, strokePaint, const Offset(45, 620), 30, math.pi / 4);
    _drawCapsule(canvas, strokePaint, fillPaint, const Offset(80, 670), 28, 12, -math.pi / 6);
    _drawCross(canvas, strokePaint, const Offset(25, 690), 14);

    _drawCapsule(canvas, strokePaint, fillPaint, Offset(size.width - 55, 610), 30, 13, math.pi / 3);
    _drawLeaf(canvas, strokePaint, Offset(size.width - 85, 660), 26, -math.pi / 4);
    _drawPill(canvas, strokePaint, fillPaint, Offset(size.width - 30, 680), 22, 10, math.pi / 8);

    // Petits cercles et étincelles décoratives
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    final dots = [
      const Offset(70, 95),
      const Offset(25, 170),
      Offset(size.width - 60, 160),
      Offset(size.width - 20, 480),
      const Offset(35, 470),
      Offset(size.width - 70, 550),
      const Offset(60, 560),
    ];

    for (final d in dots) {
      canvas.drawCircle(d, 2.5, dotPaint);
    }
  }

  void _drawLeaf(Canvas canvas, Paint stroke, Offset center, double size, double angle) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final path = Path();
    path.moveTo(0, -size / 2);
    path.quadraticBezierTo(size / 2, 0, 0, size / 2);
    path.quadraticBezierTo(-size / 2, 0, 0, -size / 2);

    canvas.drawPath(path, stroke);
    canvas.drawLine(Offset(0, -size / 2), Offset(0, size / 2), stroke);
    canvas.restore();
  }

  void _drawCapsule(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Offset center,
    double length,
    double radius,
    double angle,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: length, height: radius * 2),
      Radius.circular(radius),
    );

    canvas.drawRRect(rrect, fill);
    canvas.drawRRect(rrect, stroke);
    canvas.drawLine(Offset(0, -radius), Offset(0, radius), stroke);
    canvas.restore();
  }

  void _drawPill(
    Canvas canvas,
    Paint stroke,
    Paint fill,
    Offset center,
    double width,
    double height,
    double angle,
  ) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final rect = Rect.fromCenter(center: Offset.zero, width: width, height: height * 2);
    canvas.drawOval(rect, fill);
    canvas.drawOval(rect, stroke);
    canvas.drawLine(Offset(-width / 2, 0), Offset(width / 2, 0), stroke);
    canvas.restore();
  }

  void _drawCross(Canvas canvas, Paint stroke, Offset center, double size) {
    canvas.drawLine(
      Offset(center.dx - size / 2, center.dy),
      Offset(center.dx + size / 2, center.dy),
      stroke,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - size / 2),
      Offset(center.dx, center.dy + size / 2),
      stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
