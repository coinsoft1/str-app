// lib/screens/login_screen.dart
import 'dart:math'; // ADDED THIS LINE
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/onboarding_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _familyCodeController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscurePassword = true;
  bool _isKidMode = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    _familyCodeController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await _navigateToDashboard();

    } catch (e) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (FirebaseAuth.instance.currentUser != null) {
        print('✅ Login succeeded despite SDK error');
        await _navigateToDashboard();
      } else {
        _showError('Sign in failed. Check email and password.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithUsername() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final username = _usernameController.text.trim().toLowerCase();
      final familyCode = _familyCodeController.text.trim().toUpperCase();
      final email = '$username@$familyCode.strapp.com';

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      await _navigateToDashboard();

    } catch (e) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (FirebaseAuth.instance.currentUser != null) {
        print('✅ Login succeeded despite SDK error');
        await _navigateToDashboard();
      } else {
        _showError('Sign in failed. Check username, family code, and password.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToDashboard() async {
    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showError('Login failed: No user found');
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      String route;
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>?;
        final role = data?['role'] as String?;

        if (role == 'parent') {
          route = '/parent_dashboard';
        } else if (role == 'child') {
          route = '/child_dashboard';
        } else {
          route = '/login';
        }
      } else {
        route = '/login';
      }

      Navigator.of(context).pushNamedAndRemoveUntil(route, (route) => false);

    } catch (e) {
      print('❌ Navigation error: $e');
      _showError('Login succeeded but failed to load dashboard. Please restart app.');
    }
  }

  Future<void> _signUpWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final familyCode = String.fromCharCodes(
          Iterable.generate(6, (_) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'.codeUnitAt(Random().nextInt(36)))
      );

      final familyRef = FirebaseFirestore.instance.collection('families').doc();
      await familyRef.set({
        'createdBy': cred.user!.uid,
        'members': [cred.user!.uid],
        'parentIds': [cred.user!.uid],
        'childIds': [],
        'familyCode': familyCode,
        'createdAt': FieldValue.serverTimestamp(),
        'name': 'My Family',
      });

      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'email': _emailController.text.trim(),
        'displayName': _emailController.text.trim().split('@')[0],
        'username': _emailController.text.trim().split('@')[0],
        'createdAt': FieldValue.serverTimestamp(),
        'role': 'parent',
        'familyId': familyRef.id,
        'currentPoints': 0,
        'totalPoints': 0,
        'hasSeenOnboarding': false,
      });

      if (mounted) {
        await _showParentWelcomeDialog(familyCode);
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Sign up failed');
    } catch (e) {
      _showError('Sign up failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showParentWelcomeDialog(String familyCode) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '🎉 Welcome!',
                style: TextStyle(fontSize: 48),
              ),
              const SizedBox(height: 16),
              const Text(
                'You\'re Building Healthier Habits',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'By using STR, you\'re taking a powerful step toward balanced screen time for your family. Set goals, reward progress, and watch your children thrive!',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your Family Code',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      familyCode,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Share this with your children',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showParentTutorial();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('See How It Works', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showParentTutorial() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          pages: [
            OnboardingPage(
              title: 'Set Goals & Limits',
              description: 'Create screen time goals for your children. Set daily limits and choose rewards they can earn by staying within bounds.',
              icon: Icons.flag,
              color: Colors.teal,
            ),
            OnboardingPage(
              title: 'Assign Tasks',
              description: 'Create tasks like homework, chores, or reading. Each completed task earns points toward rewards.',
              icon: Icons.checklist,
              color: Colors.blue,
            ),
            OnboardingPage(
              title: 'Review & Verify',
              description: 'Your child logs their own screen time. You review and verify entries to build trust and accountability.',
              icon: Icons.verified_user,
              color: Colors.orange,
            ),
            OnboardingPage(
              title: 'Analytics & Reports',
              description: 'Track educational vs entertainment usage over time. Export weekly or monthly reports to see progress.',
              icon: Icons.analytics,
              color: Colors.indigo,
              customContent: _buildAnalyticsPreview(),
            ),
            OnboardingPage(
              title: 'Stay Notified',
              description: 'Get instant alerts when your child completes tasks, redeems rewards, or wins bonus spins on the reward wheel.',
              icon: Icons.notifications,
              color: Colors.green,
            ),
          ],
          onComplete: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                'hasSeenOnboarding': true,
              });
            }
            Navigator.of(context).pushNamedAndRemoveUntil('/parent_dashboard', (route) => false);
          },
          onSkip: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                'hasSeenOnboarding': true,
              });
            }
            Navigator.of(context).pushNamedAndRemoveUntil('/parent_dashboard', (route) => false);
          },
          completeButtonText: 'Go to Dashboard',
        ),
      ),
    );
  }

  Widget _buildAnalyticsPreview() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildFakeBar('Mon', 0.4, Colors.blue),
            _buildFakeBar('Tue', 0.7, Colors.blue),
            _buildFakeBar('Wed', 0.5, Colors.orange),
            _buildFakeBar('Thu', 0.3, Colors.blue),
            _buildFakeBar('Fri', 0.6, Colors.orange),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLegend('Educational', Colors.blue),
            const SizedBox(width: 16),
            _buildLegend('Entertainment', Colors.orange),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.summarize, size: 20, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Weekly Summary: 45 min Educational, 30 min Entertainment',
                  style: TextStyle(fontSize: 12, color: Colors.indigo.shade800),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFakeBar(String day, double height, Color color) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 60 * height,
          decoration: BoxDecoration(
            color: color.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 4),
        Text(day, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
      ],
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF3E5F5),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.amber.shade100,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.star,
                      size: 40,
                      color: Colors.amber.shade700,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'STR',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                      letterSpacing: 2,
                    ),
                  ),

                  Text(
                    'Screen Time Rewards',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.purple.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 32),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isKidMode = false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_isKidMode ? const Color(0xFF6A1B9A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Parent/Email',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !_isKidMode ? Colors.white : Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _isKidMode = true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _isKidMode ? const Color(0xFF6A1B9A) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Kid/Username',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _isKidMode ? Colors.white : Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            Text(
                              _isSignUp ? 'Create Account' : 'Welcome Back',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isKidMode
                                  ? 'Enter your username and family code'
                                  : (_isSignUp ? 'Start managing screen time' : 'Sign in to continue'),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 24),

                            if (!_isKidMode) ...[
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                validator: (val) => val?.isEmpty ?? true ? 'Enter email' : null,
                                decoration: InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: const Icon(Icons.email, color: Color(0xFF6A1B9A)),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                              ),
                            ] else ...[
                              TextFormField(
                                controller: _usernameController,
                                textInputAction: TextInputAction.next,
                                validator: (val) => val?.isEmpty ?? true ? 'Enter username' : null,
                                decoration: InputDecoration(
                                  labelText: 'Username',
                                  prefixIcon: const Icon(Icons.person, color: Color(0xFF6A1B9A)),
                                  hintText: 'e.g., johnny',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _familyCodeController,
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 6,
                                validator: (val) => val?.length != 6 ? 'Enter 6-character family code' : null,
                                decoration: InputDecoration(
                                  labelText: 'Family Code',
                                  prefixIcon: const Icon(Icons.family_restroom, color: Color(0xFF6A1B9A)),
                                  hintText: 'e.g., 4DPBCS',
                                  counterText: '',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              validator: (val) => (val?.length ?? 0) < 6 ? 'Min 6 characters' : null,
                              decoration: InputDecoration(
                                labelText: _isKidMode ? 'Password or PIN' : 'Password',
                                prefixIcon: const Icon(Icons.lock, color: Color(0xFF6A1B9A)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                              ),
                            ),
                            const SizedBox(height: 24),

                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : (_isKidMode
                                    ? _signInWithUsername
                                    : (_isSignUp ? _signUpWithEmail : _signInWithEmail)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6A1B9A),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                                    : Text(
                                  _isSignUp ? 'Create Account' : 'Sign In',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),

                            if (!_isKidMode) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                                child: Text(
                                  _isSignUp
                                      ? 'Already have an account? Sign In'
                                      : 'New family? Create Account',
                                  style: const TextStyle(color: Color(0xFF6A1B9A)),
                                ),
                              ),
                            ],

                            if (_isKidMode) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(context, '/role_selection');
                                },
                                child: const Text(
                                  'New kid? Join Family Here',
                                  style: TextStyle(color: Color(0xFF6A1B9A)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.family_restroom, size: 16, color: Colors.purple.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'Parents can create family codes for kids',
                        style: TextStyle(
                          color: Colors.purple.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}