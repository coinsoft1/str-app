import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'child_dashboard.dart';
import 'parent_dashboard.dart';
import 'dart:math';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({Key? key}) : super(key: key);

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final _familyCodeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = false;
  bool _isCreatingChildAccount = false;
  String? _generatedFamilyCode;
  String? _errorMessage;
  bool _usePin = false;

  @override
  void dispose() {
    _familyCodeController.dispose();
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _generateFamilyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _selectParentRole() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final familyCode = _generateFamilyCode();
      final familyId = 'FAM${DateTime.now().millisecondsSinceEpoch}';
      
      await FirebaseFirestore.instance.collection('families').doc(familyId).set({
        'familyId': familyId,
        'familyCode': familyCode,
        'familyName': '${user.email?.split('@')[0] ?? 'My'} Family',
        'parentIds': [user.uid],
        'childIds': [],
        'members': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': user.uid,
      });

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      
      if (userDoc.exists) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'role': 'parent',
          'familyId': familyId,
          'displayName': user.email?.split('@')[0] ?? 'Parent',
          'username': user.email?.split('@')[0] ?? 'parent',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'role': 'parent',
          'familyId': familyId,
          'displayName': user.email?.split('@')[0] ?? 'Parent',
          'username': user.email?.split('@')[0] ?? 'parent',
          'createdAt': FieldValue.serverTimestamp(),
          'currentPoints': 0,
          'members': [user.uid],
        });
      }

      setState(() {
        _generatedFamilyCode = familyCode;
        _isLoading = false;
      });

      _showFamilyCodeDialog(familyCode);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error creating family: $e';
      });
    }
  }

  // DEFINITIVE FIX: Treat ANY auth error as potential Pigeon bug, check currentUser regardless
  Future<void> _createChildAccount() async {
    if (_usernameController.text.trim().length < 3) {
      setState(() => _errorMessage = 'Username must be at least 3 characters');
      return;
    }
    if (_displayNameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (_familyCodeController.text.trim().length != 6) {
      setState(() => _errorMessage = 'Please enter a valid 6-character family code');
      return;
    }
    if (_passwordController.text.length < 6) {
      setState(() => _errorMessage = 'Password/PIN must be at least 6 characters');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim().toLowerCase();
    final displayName = _displayNameController.text.trim();
    final familyCode = _familyCodeController.text.trim().toUpperCase();
    final password = _passwordController.text;
    final email = '$username@$familyCode.strapp.com';
    
    User? firebaseUser;

    try {
      // Attempt 1: Try to create user (may throw PigeonUserDetails error)
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      // ANY error here (including PigeonUserDetails) is caught but ignored
      // because the user IS being created in Firebase Auth despite the SDK crash
      print('Auth creation error (ignored): $e');
    }

    // CRITICAL: Wait for auth state to settle then check currentUser
    await Future.delayed(const Duration(milliseconds: 1500));
    
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.email?.toLowerCase() == email.toLowerCase()) {
      firebaseUser = currentUser;
      print('SUCCESS: User found after creation: ${firebaseUser.uid}');
    }

    // If no user found after waiting, show error
    if (firebaseUser == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to create account. Please check your connection and try again.';
      });
      return;
    }

    // Continue with Firestore operations (may also fail due to rules)
    try {
      // Verify family code
      final familyQuery = await FirebaseFirestore.instance
          .collection('families')
          .where('familyCode', isEqualTo: familyCode)
          .limit(1)
          .get();

      if (familyQuery.docs.isEmpty) {
        await FirebaseAuth.instance.signOut();
        try { await firebaseUser.delete(); } catch (_) {}
        setState(() {
          _isLoading = false;
          _errorMessage = 'Family code not found. Please check and try again.';
        });
        return;
      }

      final familyDoc = familyQuery.docs.first;
      final familyData = familyDoc.data() as Map<String, dynamic>? ?? {};
      
      String parentId = '';
      if (familyData.containsKey('parentIds')) {
        final parentIdsList = familyData['parentIds'] as List<dynamic>?;
        if (parentIdsList != null && parentIdsList.isNotEmpty) {
          parentId = parentIdsList.first.toString();
        }
      }
      
      if (parentId.isEmpty && familyData.containsKey('createdBy')) {
        parentId = familyData['createdBy'].toString();
      }
      
      if (parentId.isEmpty) {
        throw Exception('Invalid family data: no parent found');
      }

      // Check username uniqueness
      final existingUser = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .where('familyId', isEqualTo: familyDoc.id)
          .get();

      if (existingUser.docs.isNotEmpty) {
        await FirebaseAuth.instance.signOut();
        try { await firebaseUser.delete(); } catch (_) {}
        setState(() {
          _isLoading = false;
          _errorMessage = 'Username already taken in this family. Choose another.';
        });
        return;
      }

      // Create user document in Firestore
      await FirebaseFirestore.instance.collection('users').doc(firebaseUser.uid).set({
        'email': email,
        'username': username,
        'displayName': displayName,
        'role': 'child',
        'familyId': familyDoc.id,
        'parentId': parentId,
        'createdAt': FieldValue.serverTimestamp(),
        'currentPoints': 0,
        'dailyScreenTimeLimit': 60,
        'authMethod': _usePin ? 'pin' : 'password',
      });

      // Update family document
      await FirebaseFirestore.instance.collection('families').doc(familyDoc.id).update({
        'childIds': FieldValue.arrayUnion([firebaseUser.uid]),
        'members': FieldValue.arrayUnion([firebaseUser.uid]),
      });

      setState(() => _isLoading = false);
      
      // Navigate to child dashboard
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const ChildDashboard()),
          (route) => false,
        );
      }
      
    } catch (e) {
      print('Firestore error: $e');
      // Cleanup orphaned auth account
      try {
        await FirebaseAuth.instance.signOut();
        await firebaseUser.delete();
      } catch (_) {}
      
      setState(() {
        _isLoading = false;
        _errorMessage = 'Setup error: $e';
      });
    }
  }

  void _showFamilyCodeDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.celebration, color: Colors.amber),
            SizedBox(width: 8),
            Text('Family Created!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Share this code with your children:'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  color: Color(0xFF6A1B9A),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'They will need this to join your family',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const ParentDashboard()),
                (route) => false,
              );
            },
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      debugPrint('Sign out error: $e');
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  void _goBack() {
    Navigator.of(context).pushReplacementNamed('/login');
  }

  Widget _buildChildSignupForm() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Join Your Family',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF6A1B9A),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _displayNameController,
              decoration: InputDecoration(
                labelText: 'Your Name',
                hintText: 'e.g., Johnny Smith',
                prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Choose Username',
                hintText: 'e.g., johnny',
                prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                helperText: 'Unique within your family',
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _familyCodeController,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: 'Family Code',
                hintText: 'e.g., 4DPBCS',
                prefixIcon: const Icon(Icons.family_restroom, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Password'),
                  selected: !_usePin,
                  onSelected: (selected) => setState(() => _usePin = !selected),
                  selectedColor: Colors.purple.shade100,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('6-Digit PIN'),
                  selected: _usePin,
                  onSelected: (selected) => setState(() => _usePin = selected),
                  selectedColor: Colors.purple.shade100,
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _passwordController,
              obscureText: true,
              keyboardType: _usePin ? TextInputType.number : TextInputType.text,
              maxLength: _usePin ? 6 : null,
              decoration: InputDecoration(
                labelText: _usePin ? '6-Digit PIN' : 'Password',
                hintText: _usePin ? '123456' : 'Min 6 characters',
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            
            TextField(
              controller: _confirmPasswordController,
              obscureText: true,
              keyboardType: _usePin ? TextInputType.number : TextInputType.text,
              maxLength: _usePin ? 6 : null,
              decoration: InputDecoration(
                labelText: _usePin ? 'Confirm 6-Digit PIN' : 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF6A1B9A)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createChildAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Join Family', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => setState(() => _isCreatingChildAccount = false),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3E5F5),
      appBar: AppBar(
        title: const Text('Who are you?'),
        backgroundColor: const Color(0xFFF3E5F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6A1B9A)),
          onPressed: _goBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF6A1B9A)),
            onPressed: _signOut,
            tooltip: 'Sign Out',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: SingleChildScrollView(
            child: Column(
              children: [
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.red, size: 18),
                          onPressed: () => setState(() => _errorMessage = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                
                if (_isCreatingChildAccount) ...[
                  _buildChildSignupForm(),
                ] else ...[
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: InkWell(
                      onTap: _isLoading ? null : _selectParentRole,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.person, size: 35, color: Colors.blue.shade700),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Parent',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create a family and manage screen time',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                            ),
                            if (_isLoading && _generatedFamilyCode == null) ...[
                              const SizedBox(height: 16),
                              const CircularProgressIndicator(),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.child_care, size: 35, color: Colors.orange.shade700),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Child',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6A1B9A),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Join your family with a code',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: 160,
                            height: 44,
                            child: ElevatedButton.icon(
                              onPressed: () => setState(() => _isCreatingChildAccount = true),
                              icon: const Icon(Icons.login, size: 18),
                              label: const Text('Join Family', style: TextStyle(fontSize: 15)),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.orange.shade800,
                                backgroundColor: Colors.orange.shade50,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: Colors.orange.shade300),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}