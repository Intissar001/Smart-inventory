import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool isSignIn = true;
  bool showPassword = false;

  final Color bgGrey       = const Color(0xDF939090);
  final Color brownShadow  = const Color(0xE2030303);
  final Color bioBlueFaded = const Color(0xFF5C9DED);

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController           = TextEditingController();
  final TextEditingController _passwordController        = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);

    if (isSignIn) {
      // ── Sign In ──────────────────────────────────────────────────────────
      final error = await auth.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        return;
      }
      // Only navigate to dashboard after a successful LOGIN
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/dashboard');
      }
    } else {
      // ── Register ─────────────────────────────────────────────────────────
      final error = await auth.register(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
        return;
      }
      // After successful registration → switch to Sign In and show confirmation
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Account created! Please sign in."),
            backgroundColor: Color(0xFF10B981),
          ),
        );
        setState(() {
          isSignIn = true;
          showPassword = false;
          _passwordController.clear();
          _confirmPasswordController.clear();
          _formKey.currentState?.reset();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgGrey,
      body: Stack(
        children: [
          _buildAnimatedBackground(),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 32),
                  Text(
                    isSignIn ? "Welcome Back" : "Create Account",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isSignIn
                        ? "Sign in to access your inventory"
                        : "Join to manage your inventory",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.6), fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel("Email Address"),
                        _buildTextField(
                          hint: "you@example.com",
                          icon: Icons.mail_outline,
                          controller: _emailController,
                          validator: (value) {
                            if (value == null || value.isEmpty)
                              return "Please enter your email";
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildLabel("Password"),
                        _buildTextField(
                          hint: "Enter your password",
                          icon: Icons.lock_outline,
                          controller: _passwordController,
                          isPassword: true,
                          validator: (value) {
                            if (value == null || value.isEmpty)
                              return "Please enter your password";
                            if (value.length < 6)
                              return "Password must be at least 6 characters";
                            return null;
                          },
                        ),
                        if (!isSignIn) ...[
                          const SizedBox(height: 20),
                          _buildLabel("Confirm Password"),
                          _buildTextField(
                            hint: "Confirm your password",
                            icon: Icons.lock_outline,
                            controller: _confirmPasswordController,
                            isPassword: true,
                            validator: (value) {
                              if (value != _passwordController.text)
                                return "Passwords do not match";
                              return null;
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildSubmitButton(),
                  const SizedBox(height: 24),
                  _buildModeSwitcher(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgGrey, brownShadow, const Color(0xFF1A1A1A)],
        ),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
        child: Container(color: Colors.black.withOpacity(0.1)),
      ),
    );
  }

  Widget _buildLogo() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10))
        ],
      ),
      child: ClipOval(
        child: Image.asset('assets/authlogo.png', fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(text,
          style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildTextField({
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    bool isPassword = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: isPassword && !showPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
        prefixIcon:
            Icon(icon, color: bioBlueFaded.withOpacity(0.7), size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                    showPassword
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: Colors.white.withOpacity(0.3)),
                onPressed: () =>
                    setState(() => showPassword = !showPassword),
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: Colors.white.withOpacity(0.05))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide:
                BorderSide(color: bioBlueFaded.withOpacity(0.5))),
        errorStyle: const TextStyle(color: Colors.redAccent),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 58,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5))
        ],
      ),
      child: ElevatedButton(
        onPressed: _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: bgGrey,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ).copyWith(
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
        ),
        child: Text(
          isSignIn ? "SIGN IN" : "GET STARTED",
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2),
        ),
      ),
    );
  }

  Widget _buildModeSwitcher() {
    return TextButton(
      onPressed: () => setState(() {
        isSignIn = !isSignIn;
        showPassword = false;
        _formKey.currentState?.reset();
        _emailController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
      }),
      style: ButtonStyle(
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
      ),
      child: RichText(
        text: TextSpan(
          text: isSignIn
              ? "Don't have an account? "
              : "Already have an account? ",
          style: TextStyle(color: Colors.white.withOpacity(0.5)),
          children: [
            TextSpan(
              text: isSignIn ? "Sign Up" : "Sign In",
              style: TextStyle(
                  color: bioBlueFaded, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}