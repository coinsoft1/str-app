// lib/screens/role_selection_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../widgets/onboarding_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final _familyCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _familyCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _createChildAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim().toLowerCase();
    final familyCode = _familyCodeController.text.trim().toUpperCase();
    final password = _passwordController.text.trim();
    final email = '$username@$familyCode.strapp.com';

    try {
      UserCredential cred;
      try {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'email-already-in-use') {
          _showError('This username is already taken in your family. Choose another.');
        } else {
          _showError(e.message ?? 'Account creation failed');
        }
        setState(() => _isLoading = false);
        return;
      }

      final familyQuery = await FirebaseFirestore.instance
          .collection('families')
          .where('familyCode', isEqualTo: familyCode)
          .limit(1)
          .get();

      if (familyQuery.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        _showError('Invalid family code. Please check with your parent.');
        setState(() => _isLoading = false);
        return;
      }

      final familyDoc = familyQuery.docs.first;
      final familyId = familyDoc.id;
      final familyData = familyDoc.data();
      final parentId = (familyData['parentIds'] as List<dynamic>?)?.first ??
          (familyData['createdBy'] as String?);

      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'username': username,
        'displayName': username,
        'name': username,
        'email': email,
        'role': 'child',
        'familyId': familyId,
        'parentId': parentId,
        'currentPoints': 0,
        'totalPoints': 0,
        'lifetimePoints': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'hasSeenOnboarding': false,
      });

      await familyDoc.reference.update({
        'members': FieldValue.arrayUnion([cred.user!.uid]),
        'childIds': FieldValue.arrayUnion([cred.user!.uid]),
      });

      // NEW: Send in-app notification to parent
      if (parentId != null && parentId.isNotEmpty) {
        try {
          await FirebaseFirestore.instance.collection('notifications').add({
            'type': 'child_joined',
            'title': '👋 New Family Member!',
            'message': '$username just joined your family. Welcome them to STR!',
            'parentId': parentId,
            'childId': cred.user!.uid,
            'childName': username,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (e) {
          debugPrint('Failed to send parent notification: $e');
        }
      }

      if (mounted) {
        await _showWelcomeDialog();
        _showChildTutorial();
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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

  // Welcome graffiti dialog
  Future<void> _showWelcomeDialog() async {
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
                '🎨 Welcome!',
                style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'You joined the family!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A1B9A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Get ready to earn rewards by managing your screen time wisely.',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6A1B9A),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(200, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Let\'s Go!', style: TextStyle(fontSize: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NEW: Child tutorial
  void _showChildTutorial() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OnboardingScreen(
          pages: [
            OnboardingPage(
              title: 'Log Your Screen Time',
              description: 'After using an app, tap "Log Time" to record what you used and for how long. Be honest — it builds trust!',
              icon: Icons.add_chart,
              color: Colors.green,
            ),
            OnboardingPage(
              title: 'Complete Tasks',
              description: 'Your parent will assign tasks like homework or chores. Complete them to earn points for rewards.',
              icon: Icons.checklist,
              color: Colors.blue,
            ),
            OnboardingPage(
              title: 'Spin the Wheel',
              description: 'Earn bonus rewards by spinning the reward wheel. No points needed — just a fun surprise!',
              icon: Icons.casino,
              color: Colors.purple,
            ),
            OnboardingPage(
              title: 'Redeem Rewards',
              description: 'Use your earned points to claim rewards your parent set up. From extra playtime to treats!',
              icon: Icons.card_giftcard,
              color: Colors.amber,
            ),
          ],
          onComplete: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                'hasSeenOnboarding': true,
              });
            }
            Navigator.of(context).pushNamedAndRemoveUntil('/child_dashboard', (route) => false);
          },
          onSkip: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                'hasSeenOnboarding': true,
              });
            }
            Navigator.of(context).pushNamedAndRemoveUntil('/child_dashboard', (route) => false);
          },
          completeButtonText: 'Start My Journey',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6A1B9A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Join Family',
          style: TextStyle(color: Color(0xFF6A1B9A), fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
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
                    child: Icon(Icons.family_restroom, size: 40, color: Colors.amber.shade700),
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text(
                    'Join Your Family',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Ask your parent for the family code',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _familyCodeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  validator: (val) => val?.length != 6 ? 'Enter 6-character family code' : null,
                  decoration: InputDecoration(
                    labelText: 'Family Code',
                    prefixIcon: const Icon(Icons.family_restroom, color: Color(0xFF6A1B9A)),
                    hintText: 'e.g., JLD5W3',
                    counterText: '',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _usernameController,
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val?.isEmpty ?? true) return 'Enter username';
                    if (val!.contains(' ')) return 'No spaces allowed';
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: 'Username',
                    prefixIcon: const Icon(Icons.person, color: Color(0xFF6A1B9A)),
                    hintText: 'e.g., johnny',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  validator: (val) => (val?.length ?? 0) < 6 ? 'Min 6 characters' : null,
                  decoration: InputDecoration(
                    labelText: 'Password or PIN',
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFF6A1B9A)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createChildAccount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A1B9A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                        : const Text('Join Family', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pushNamed(context, '/login'),
                    child: const Text(
                      'Already have an account? Sign In',
                      style: TextStyle(color: Color(0xFF6A1B9A)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}