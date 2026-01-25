import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  final _familyCodeController = TextEditingController();
  bool _isJoining = false;

  String _generateFamilyCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (index) => 
      chars[Random().nextInt(chars.length)]
    ).join();
  }

  Future<void> _setRole(String role) async {
    if (role == 'child' && _familyCodeController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter family code!')),
      );
      return;
    }

    setState(() => _isJoining = true);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userDoc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      
      if (role == 'parent') {
        final familyCode = _generateFamilyCode();
        final familyRef = FirebaseFirestore.instance.collection('families').doc();
        
        await familyRef.set({
          'familyName': '${user.email!.split('@')[0]}\'s Family',
          'familyCode': familyCode,
          'parentIds': [user.uid],
          'childIds': [],
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        await userDoc.update({
          'role': 'parent',
          'familyId': familyRef.id,
        });
      } else {
        final familyCode = _familyCodeController.text.toUpperCase().trim();
        
        final familyQuery = await FirebaseFirestore.instance
            .collection('families')
            .where('familyCode', isEqualTo: familyCode)
            .limit(1)
            .get();
        
        if (familyQuery.docs.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Family not found! Check the code.')),
          );
          setState(() => _isJoining = false);
          return;
        }
        
        final familyDoc = familyQuery.docs.first;
        final familyId = familyDoc.id;
        
        await familyDoc.reference.update({
          'childIds': FieldValue.arrayUnion([user.uid]),
        });
        
        await userDoc.update({
          'role': 'child',
          'familyId': familyId,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ Role set as $role!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error: $e')),
      );
    }
    
    setState(() => _isJoining = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.purple[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, size: 80, color: Colors.purple),
                  const Text('Who are you?', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 30),
                  
                  _buildRoleCard(
                    role: 'parent',
                    icon: Icons.person,
                    title: 'Parent',
                    color: Colors.blue,
                  ),
                  
                  const SizedBox(height: 16),
                  
                  Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Container(
                      width: 280,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.child_care, size: 60, color: Colors.orange),
                          const SizedBox(height: 8),
                          const Text('Child', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('Enter your parent\'s family code:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _familyCodeController,
                            decoration: const InputDecoration(
                              labelText: 'Family Code',
                              hintText: 'e.g., AB7F9X',
                              border: OutlineInputBorder(),
                            ),
                            textAlign: TextAlign.center,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.characters,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _isJoining ? null : () => _setRole('child'),
                            child: _isJoining 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Text('Join Family'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String role,
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _isJoining ? null : () => _setRole(role),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 200,
          height: 150,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 60, color: color),
              const SizedBox(height: 8),
              Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              if (role == 'parent') ...[
                const SizedBox(height: 4),
                const Text('Create a family', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}