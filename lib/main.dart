import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import 'firebase_options.dart';
import 'screens/role_selection.dart';
import 'screens/parent_dashboard.dart';
import 'screens/child_dashboard.dart';
import 'screens/parent/admin_review_screen.dart';
import 'screens/parent/reward_management_screen.dart' as parent;
import 'screens/child/redeem_rewards_screen.dart' as child;
import 'screens/task_screen.dart';
import 'screens/create_task.dart';
import 'utils/task_templates.dart';
import 'services/deduction_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.android);
    DeductionService.startMonitoring();
    runApp(const STRApp());
  } catch (e) {
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Failed to initialize Firebase', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(e.toString(), textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class STRApp extends StatefulWidget {
  const STRApp({super.key});

  @override
  State<STRApp> createState() => _STRAppState();
}

class _STRAppState extends State<STRApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    DeductionService.stopMonitoring();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DeductionService.startMonitoring();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DeductionService.processMissedDeductions(user.uid);
      }
    } else if (state == AppLifecycleState.paused) {
      DeductionService.stopMonitoring();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STR - Screen Time Rewards',
      theme: ThemeData(
        primarySwatch: Colors.purple,
        useMaterial3: true,
      ),
      home: const AuthGate(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/role_selection': (context) => const RoleSelectionScreen(),
        '/parent_dashboard': (context) => const ParentDashboard(),
        '/child_dashboard': (context) => const ChildDashboard(),
        '/tasks': (context) => const TaskScreen(),
        '/admin_review': (context) => const AdminReviewScreen(),
        '/reward_management': (context) => const parent.RewardManagementScreen(),
        '/redeem_rewards': (context) => const child.RedeemRewardsScreen(),
        '/create_task': (context) => const CreateTaskScreen(),
      },
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('Page Not Found')),
            body: Center(child: Text('Route ${settings.name} not found')),
          ),
        );
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, authSnapshot) {
          if (authSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (!authSnapshot.hasData) {
            return const LoginScreen();
          }
          
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(authSnapshot.data!.uid).snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              
              if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
                return const LoginScreen();
              }
              
              final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
              final role = userData?['role'];
              
              if (role == null) {
                return const RoleSelectionScreen();
              } else if (role == 'parent') {
                return const ParentDashboard();
              } else if (role == 'child') {
                return const ChildDashboard();
              } else {
                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        const Text('Invalid user role', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text('Role "$role" is not recognized', style: TextStyle(color: Colors.grey[600])),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    
    try {
      UserCredential userCredential;
      if (_isLogin) {
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
        
        final displayName = _nameController.text.trim().isNotEmpty 
            ? _nameController.text.trim() 
            : _emailController.text.split('@')[0];
            
        await userCredential.user?.updateDisplayName(displayName);
        
        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'email': _emailController.text.trim(),
          'role': null,
          'name': displayName,
          'totalPoints': 0,
          'currentPoints': 0,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        String message = e.message ?? 'An error occurred';
        if (e.code == 'user-not-found') message = 'No user found with this email';
        else if (e.code == 'wrong-password') message = 'Incorrect password';
        else if (e.code == 'email-already-in-use') message = 'This email is already registered';
        else if (e.code == 'invalid-email') message = 'Invalid email address';
        else if (e.code == 'weak-password') message = 'Password should be at least 6 characters';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.red, duration: const Duration(seconds: 3)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 80, color: Colors.purple),
                  const SizedBox(height: 16),
                  const Text('STR', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.purple)),
                  const SizedBox(height: 8),
                  Text('Screen Time Rewards', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                  const SizedBox(height: 40),
                  
                  if (!_isLogin) ...[
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return 'Please enter your name';
                        if (value.trim().length < 2) return 'Name must be at least 2 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email)),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter your email';
                      if (!value.contains('@')) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 16),
                  
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter your password';
                      if (value.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submit,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                            minimumSize: const Size(double.infinity, 50),
                          ),
                          child: Text(_isLogin ? 'Login' : 'Sign Up'),
                        ),
                  
                  const SizedBox(height: 16),
                  
                  TextButton(
                    onPressed: () => setState(() => _isLogin = !_isLogin),
                    child: Text(_isLogin ? 'Need an account? Sign up' : 'Have an account? Login'),
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