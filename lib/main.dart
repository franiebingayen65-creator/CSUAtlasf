import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csuatlasf/admin_dashboard.dart';
import 'package:csuatlasf/org_dashboard.dart';
import 'package:csuatlasf/account_settings_page.dart';
import 'package:csuatlasf/utils/app_utils.dart';

const bool kAlwaysRequireLogin = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lriowumebzpwxlgcided.supabase.co',
    // cspell:disable-next-line
    publishableKey: 'sb_publishable_oGW_4BK6w8bxfDj7JHm9Tw_Ez5eCVEJ',
  );

  if (kAlwaysRequireLogin) {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Ignore: offline or no session.
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ATLAS Portal',
      theme: ThemeData(
        fontFamily: 'sans-serif',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4338CA),
          brightness: Brightness.light,
        ),
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/dashboard': (context) => const AdminDashboard(),
        '/org_dashboard': (context) => const OrgDashboard(),
        '/account': (context) => const AccountSettingsPage(),
      },
    );
  }
}

/// Design tokens for the login screen.
class _T {
  static const navy = Color(0xFF0F172A);
  static const navyMid = Color(0xFF1E1B4B);
  static const indigo = Color(0xFF4338CA);
  static const indigoHover = Color(0xFF3730A3);
  static const indigoPressed = Color(0xFF312E81);
  static const violet = Color(0xFF6366F1);
  static const sky = Color(0xFF38BDF8);

  static const textPrimary = Color(0xFF0F172A);
  static const textSecondary = Color(0xFF64748B);
  static const textLabel = Color(0xFF334155);
  static const hint = Color(0xFF94A3B8);
  static const border = Color(0xFFE2E8F0);
  static const inputFill = Color(0xFFF8FAFC);
  static const inputFillDisabled = Color(0xFFF1F5F9);
  static const error = Color(0xFFEF4444);

  static const cardRadius = 24.0;
  static const fieldRadius = 12.0;
  static const fieldHeightPad = 15.0;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isPasswordObscured = true;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;

  static const _domains = ['csu.edu.ph', 'gmail.com'];
  String _domain = _domains.first;

  @override
  void initState() {
    super.initState();
    if (!kAlwaysRequireLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfSignedIn());
    }
  }

  String? _routeForRole(String? role) {
    final r = (role ?? '').toString().toLowerCase().trim();
    if (r == 'admin' || r == 'administrator') {
      return '/dashboard';
    }
    if (r == 'president' || r == 'adviser') {
      return '/org_dashboard';
    }
    return null;
  }

  Future<void> _redirectIfSignedIn() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return;
    try {
      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final route = _routeForRole(profile?['role']?.toString());
      if (!mounted) return;
      if (route != null) {
        Navigator.pushReplacementNamed(context, route);
      } else {
        await client.auth.signOut();
      }
    } catch (_) {
      // Stay on login page if query fails.
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final input = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final email = input.contains('@') ? input : '$input@$_domain';
    final client = Supabase.instance.client;

    try {
      final response = await client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      final user = response.user;
      if (user == null) throw const AuthException('Invalid login credentials.');

      final profile = await client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final role = profile?['role']?.toString();
      final route = _routeForRole(role);
      if (!mounted) return;

      if (route == null) {
        await client.auth.signOut();
        if (mounted) {
          AppUtils.showTopToast(context, 'Access denied: Unauthorized role.', isError: true);
        }
        return;
      }

      AppUtils.showTopToast(
        context,
        role == 'Admin' ? 'Login successful! Welcome Admin.' : 'Login successful! Welcome to the portal.',
      );
      Navigator.pushReplacementNamed(context, route);
    } on AuthException catch (e) {
      if (mounted) {
        final msg = e.message.toLowerCase();
        final displayMsg = msg.contains('invalid login') || msg.contains('invalid credentials')
            ? 'Invalid email/username or password.'
            : e.message;
        AppUtils.showTopToast(context, displayMsg, isError: true);
        _passwordFocus.requestFocus();
      }
    } catch (_) {
      if (mounted) {
        AppUtils.showTopToast(context, 'Something went wrong. Please try again.', isError: true);
        _passwordFocus.requestFocus();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // ───────────────────────── BUILD ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.navy,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_T.navy, _T.navyMid, _T.navy],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              right: -100,
              child: _blob(420, _T.violet.withValues(alpha: 0.12)),
            ),
            Positioned(
              bottom: -120,
              left: -100,
              child: _blob(360, _T.sky.withValues(alpha: 0.07)),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final isWide = w >= 760;
                  final isDesktop = w >= 1000;
                  final hMargin = w < 480 ? 16.0 : 24.0;

                  final card = _buildCard(
                    isWide: isWide,
                    isDesktop: isDesktop,
                    availableHeight: constraints.maxHeight,
                  );

                  return SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: hMargin,
                            vertical: 24,
                          ),
                          child: card,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blob(double size, Color color) => IgnorePointer(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    ),
  );

  Widget _buildCard({
    required bool isWide,
    required bool isDesktop,
    required double availableHeight,
  }) {
    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(_T.cardRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.28),
          blurRadius: 48,
          spreadRadius: -4,
          offset: const Offset(0, 24),
        ),
      ],
    );

    if (!isWide) {
      // Mobile: compact branding header above the form, natural height.
      return Container(
        constraints: const BoxConstraints(maxWidth: 480),
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: decoration,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCompactHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
              child: _buildForm(),
            ),
          ],
        ),
      );
    }

    // Tablet / desktop: two columns with bounded height.
    final cardHeight = (availableHeight - 48).clamp(520.0, 640.0);
    return Container(
      constraints: BoxConstraints(maxWidth: isDesktop ? 980 : 800),
      width: double.infinity,
      height: cardHeight,
      clipBehavior: Clip.antiAlias,
      decoration: decoration,
      child: Row(
        children: [
          Expanded(
            flex: 11,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isDesktop ? 56 : 36,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: _buildForm(),
                ),
              ),
            ),
          ),
          Expanded(
            flex: isDesktop ? 10 : 9,
            child: _buildBrandPanel(isDesktop: isDesktop),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── FORM ─────────────────────────

  Widget _buildForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome back',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: _T.textPrimary,
                letterSpacing: -0.6,
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to access your dashboard and organization tools.',
              style: TextStyle(
                color: _T.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            _buildInputField(
              controller: _usernameController,
              focusNode: _usernameFocus,
              label: 'Email or Username',
              hintText: 'Enter your ID or email',
              icon: Icons.alternate_email_rounded,
              autofillHints: const [AutofillHints.username, AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Please enter your email or username'
                  : null,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              suffix: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _usernameController,
                builder: (context, value, _) => value.text.contains('@')
                    ? const SizedBox.shrink()
                    : _buildDomainPicker(),
              ),
            ),
            const SizedBox(height: 8),
            _buildInputField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              label: 'Password',
              hintText: 'Enter your password',
              icon: Icons.lock_outline_rounded,
              isPassword: true,
              obscureText: _isPasswordObscured,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onToggle: () =>
                  setState(() => _isPasswordObscured = !_isPasswordObscured),
              validator: (v) =>
              v == null || v.isEmpty ? 'Please enter your password' : null,
              onSubmitted: (_) {
                if (!_isLoading) _handleLogin();
              },
            ),
            const SizedBox(height: 20),
            _buildSignInButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDomainPicker() {
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: PopupMenuButton<String>(
        enabled: !_isLoading,
        tooltip: 'Choose email domain',
        initialValue: _domain,
        onSelected: (v) => setState(() => _domain = v),
        itemBuilder: (context) => [
          for (final d in _domains)
            PopupMenuItem<String>(value: d, child: Text('@$d')),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '@$_domain',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _T.textSecondary,
                ),
              ),
              const Icon(
                Icons.arrow_drop_down_rounded,
                size: 20,
                color: _T.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ButtonStyle(
          elevation: const WidgetStatePropertyAll(0),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_T.fieldRadius),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return _T.indigo.withValues(alpha: 0.7);
            }
            if (states.contains(WidgetState.pressed)) return _T.indigoPressed;
            if (states.contains(WidgetState.hovered)) return _T.indigoHover;
            return _T.indigo;
          }),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.06),
          ),
          mouseCursor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled)
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _isLoading
              ? Row(
            key: const ValueKey('loading'),
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'Signing in…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          )
              : const Text(
            'Sign In',
            key: ValueKey('idle'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────── BRANDING ─────────────────────────

  Widget _logo(double size) => Semantics(
    label: 'CSU university seal',
    image: true,
    child: Image.asset(
      'assets/images/csulogo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.school_rounded,
        size: size * 0.8,
        color: _T.indigo,
      ),
    ),
  );

  Widget _buildBrandPanel({required bool isDesktop}) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: _T.border)),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -90,
            right: -90,
            child: _blob(260, _T.indigo.withValues(alpha: 0.05)),
          ),
          Positioned(
            bottom: -110,
            left: -70,
            child: _blob(280, _T.sky.withValues(alpha: 0.08)),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 48 : 28,
                vertical: 40,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _logo(isDesktop ? 136 : 104),
                  const SizedBox(height: 28),
                  Text(
                    'ATLAS',
                    style: TextStyle(
                      fontSize: isDesktop ? 38 : 32,
                      fontWeight: FontWeight.w900,
                      color: _T.indigo,
                      letterSpacing: 5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _T.indigo.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'A Centralized Activity Tracking,\nLiaison and Archiving System\nfor Student Organization',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isDesktop ? 17 : 15,
                      fontWeight: FontWeight.w600,
                      color: _T.textLabel,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _T.border)),
      ),
      child: Column(
        children: [
          _logo(72),
          const SizedBox(height: 14),
          const Text(
            'ATLAS',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: _T.indigo,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'A Centralized Activity Tracking,\nLiaison and Archiving System\nfor Student Organization',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: _T.textLabel,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── INPUT FIELD ─────────────────────────

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(_T.fieldRadius),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _buildInputField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggle,
    List<String>? autofillHints,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
    Widget? suffix,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _T.textLabel,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: !_isLoading,
          obscureText: obscureText,
          autofillHints: autofillHints,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          autocorrect: false,
          enableSuggestions: !isPassword,
          style: const TextStyle(fontSize: 14.5, color: _T.textPrimary),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(color: _T.hint, fontSize: 14),
            // Reserves one line so validation text doesn't shift the layout.
            helperText: ' ',
            helperStyle: const TextStyle(fontSize: 12, height: 1.1),
            errorStyle: const TextStyle(
              fontSize: 12,
              height: 1.1,
              color: _T.error,
            ),
            prefixIcon: Icon(icon, size: 19, color: _T.textSecondary),
            suffixIcon: isPassword
                ? IconButton(
              tooltip: obscureText ? 'Show password' : 'Hide password',
              icon: Icon(
                obscureText
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 19,
                color: _T.textSecondary,
              ),
              onPressed: _isLoading ? null : onToggle,
            )
                : suffix,
            filled: true,
            fillColor: _isLoading ? _T.inputFillDisabled : _T.inputFill,
            hoverColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: _T.fieldHeightPad,
              horizontal: 16,
            ),
            border: _border(_T.border),
            enabledBorder: _border(_T.border),
            disabledBorder: _border(_T.border),
            focusedBorder: _border(_T.indigo, 1.6),
            errorBorder: _border(_T.error),
            focusedErrorBorder: _border(_T.error, 1.6),
          ),
        ),
      ],
    );
  }
}