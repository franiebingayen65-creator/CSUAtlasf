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
    publishableKey: 'sb_publishable_oGW_4BK6w8bxfDj7JHm9Tw_Ez5eCVEJ',
  );

  if (kAlwaysRequireLogin) {
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      // Ignore: offline or no session. The login page will still be shown.
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
      title: 'ATLAS Login',
      theme: ThemeData(
        fontFamily: 'sans-serif',
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7A44F2)),
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (!kAlwaysRequireLogin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfSignedIn());
    }
  }

  /// Maps a profile role to its dashboard route. Returns null for unknown roles.
  String? _routeForRole(String? role) {
    switch (role) {
      case 'Admin':
        return '/dashboard';
      case 'President':
      case 'Adviser':
        return '/org_dashboard';
      default:
        return null;
    }
  }

  /// If a valid session already exists (app reopened), skip the login form.
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
      // Stay on the login page if the check fails.
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final input = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text; // do not trim passwords
    final email = input.contains('@') ? input : '$input@csu.edu.ph';
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
    } on AuthException {
      if (mounted) {
        AppUtils.showTopToast(context, 'Invalid email/username or password.', isError: true);
      }
    } catch (_) {
      if (mounted) {
        AppUtils.showTopToast(context, 'Something went wrong. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6366F1), Color(0xFFA855F7), Color(0xFFEC4899)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 600),
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 40, offset: const Offset(0, 20))],
                ),
                child: LayoutBuilder(builder: (context, constraints) {
                  final showSidePanel = constraints.maxWidth >= 700;
                  return Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(showSidePanel ? 60.0 : 28.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Welcome Back', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
                                const SizedBox(height: 8),
                                Text('Please enter your details to sign in', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                                const SizedBox(height: 48),
                                _buildInputField(
                                  controller: _usernameController,
                                  label: 'Email or Username',
                                  icon: Icons.person_outline,
                                  validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                                ),
                                const SizedBox(height: 20),
                                _buildInputField(
                                  controller: _passwordController,
                                  label: 'Password',
                                  icon: Icons.lock_outline,
                                  isPassword: true,
                                  obscureText: _isPasswordObscured,
                                  onToggle: () => setState(() => _isPasswordObscured = !_isPasswordObscured),
                                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                                  onSubmitted: (_) {
                                    if (!_isLoading) _handleLogin();
                                  },
                                ),
                                const SizedBox(height: 44),
                                SizedBox(
                                  width: double.infinity,
                                  height: 56,
                                  child: ElevatedButton(
                                    onPressed: _isLoading ? null : _handleLogin,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6366F1),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                      elevation: 0,
                                    ),
                                    child: _isLoading
                                        ? const CircularProgressIndicator(color: Colors.white)
                                        : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (showSidePanel)
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.all(60),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: Image.asset('assets/images/csulogo.png', width: 80, height: 80),
                                ),
                                const SizedBox(height: 32),
                                const Text('ATLAS', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
                                const SizedBox(height: 16),
                                Text(
                                  'A Centralized Activity Tracking, Liaison and Archiving System for Student Organizations.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.8), height: 1.6),
                                ),
                                const Spacer(),
                                Text(
                                  'CSU LAL-LO PORTAL',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggle,
    String? Function(String?)? validator,
    void Function(String)? onSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword
            ? IconButton(
          icon: Icon(obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
          onPressed: onToggle,
        )
            : null,
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey[200]!)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2)),
        floatingLabelStyle: const TextStyle(color: Color(0xFF6366F1), fontWeight: FontWeight.bold),
      ),
    );
  }
}