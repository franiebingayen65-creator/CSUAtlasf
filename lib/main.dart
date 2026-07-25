import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:csuatlasf/admin_dashboard.dart';
import 'package:csuatlasf/org_dashboard.dart';
import 'package:csuatlasf/utils/app_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://lriowumebzpwxlgcided.supabase.co',
    anonKey: 'sb_publishable_oGW_4BK6w8bxfDj7JHm9Tw_Ez5eCVEJ',
  );

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

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: _usernameController.text.contains('@') 
              ? _usernameController.text 
              : '${_usernameController.text}@csu.edu.ph', // Support both username and email
          password: _passwordController.text,
        );

        if (response.user != null) {
          // Fetch user profile to check role
          final profileData = await Supabase.instance.client
              .from('profiles')
              .select('role')
              .eq('id', response.user!.id);

          if (mounted) {
            if (profileData.isNotEmpty) {
              final profile = profileData.first;
              if (profile['role'] == 'Admin') {
                AppUtils.showTopToast(context, 'Login successful! Welcome Admin.');
                Navigator.pushReplacementNamed(context, '/dashboard');
              } else if (profile['role'] == 'President' || profile['role'] == 'Adviser') {
                AppUtils.showTopToast(context, 'Login successful! Welcome to the portal.');
                Navigator.pushReplacementNamed(context, '/org_dashboard');
              } else {
                AppUtils.showTopToast(context, 'Access denied: Unauthorized role.', isError: true);
                await Supabase.instance.client.auth.signOut();
              }
            } else {
              AppUtils.showTopToast(context, 'Profile not found. Please contact an administrator.', isError: true);
              await Supabase.instance.client.auth.signOut();
            }
          }
        }
      } on AuthException catch (error) {
        if (mounted) {
          AppUtils.showTopToast(context, error.message, isError: true);
        }
      } catch (error) {
        if (mounted) {
          AppUtils.showTopToast(context, 'Error: $error', isError: true);
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
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
            // Decorative Blobs
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
                width: 1000,
                height: 600,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 40, offset: const Offset(0, 20))],
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(60.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome Back', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Color(0xFF1E293B), letterSpacing: -0.5)),
                              const SizedBox(height: 8),
                              Text('Please enter your details to sign in', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                              const SizedBox(height: 48),
                              _buildInputField(controller: _usernameController, label: 'Email or Username', icon: Icons.person_outline, validator: (v) => v == null || v.isEmpty ? 'Required' : null),
                              const SizedBox(height: 20),
                              _buildInputField(controller: _passwordController, label: 'Password', icon: Icons.lock_outline, isPassword: true, obscureText: _isPasswordObscured, onToggle: () => setState(() => _isPasswordObscured = !_isPasswordObscured), validator: (v) => v == null || v.isEmpty ? 'Required' : null),
                              const SizedBox(height: 32),
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
                                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Sign In', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Container(
                        padding: const EdgeInsets.all(60),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false, bool obscureText = false, VoidCallback? onToggle, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword ? IconButton(icon: Icon(obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20), onPressed: onToggle) : null,
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
