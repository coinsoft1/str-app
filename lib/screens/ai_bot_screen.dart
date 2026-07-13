import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../services/ai_service.dart';

class AIBotScreen extends StatefulWidget {
  const AIBotScreen({super.key});

  @override
  State<AIBotScreen> createState() => _AIBotScreenState();
}

class _AIBotScreenState extends State<AIBotScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final AIService _aiService = AIService();
  
  bool _isTyping = false;
  String? _selectedChildId;
  List<Map<String, dynamic>> _children = [];
  bool _isInitialized = false;
  String _streamingText = '';

  @override
  void initState() {
    super.initState();
    _loadChildren();
  }

  Future<void> _loadChildren() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final children = await FirebaseFirestore.instance
        .collection('users')
        .where('parentId', isEqualTo: user.uid)
        .get();

    setState(() {
      _children = children.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'] ?? 'Child',
          'age': data['age'] ?? 10,
        };
      }).toList();
    });

    if (_children.isNotEmpty) {
      _initializeAI(_children.first);
    }
  }

  Future<void> _initializeAI(Map<String, dynamic> child) async {
    setState(() {
      _selectedChildId = child['id'] as String;
      _isInitialized = false;
      _messages.clear();
    });

    final user = FirebaseAuth.instance.currentUser;
    
    // Start streaming greeting
    final stream = await _aiService.startSmartConversation(
      childId: child['id'] as String,
      parentId: user!.uid,
      childName: child['name'] as String,
      childAge: child['age'] as int,
    );

    _handleStreamingResponse(stream, isInitialGreeting: true);
  }

  void _handleStreamingResponse(Stream<String> stream, {bool isInitialGreeting = false}) {
    setState(() {
      _isTyping = true;
      _streamingText = '';
    });

    stream.listen(
      (chunk) {
        setState(() {
          // FIXED: Use = instead of += because chunk is already the full accumulated text
          _streamingText = chunk;
        });
        _scrollToBottom();
      },
      onDone: () {
        setState(() {
          _isTyping = false;
          _messages.add({
            'text': _streamingText,
            'isUser': false,
            'timestamp': DateTime.now(),
            'isNew': true,
          });
          _streamingText = '';
          if (isInitialGreeting) _isInitialized = true;
        });
      },
      onError: (e) {
        setState(() {
          _isTyping = false;
          _messages.add({
            'text': 'Sorry, I encountered an error. Please try again.',
            'isUser': false,
            'isError': true,
          });
        });
      },
    );
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isTyping) return;

    setState(() {
      _messages.add({
        'text': message,
        'isUser': true,
        'timestamp': DateTime.now(),
      });
      _isTyping = true;
    });
    
    _messageController.clear();
    _scrollToBottom();

    final stream = await _aiService.sendMessage(message);
    _handleStreamingResponse(stream);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Parenting Coach'),
        centerTitle: true,
        actions: [
          if (_children.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.switch_account),
              onSelected: (id) {
                final child = _children.firstWhere((c) => c['id'] == id);
                _initializeAI(child);
              },
              itemBuilder: (context) => _children.map((child) => 
                PopupMenuItem(
                  value: child['id'] as String,
                  child: Text('Switch to ${child['name']}'),
                ),
              ).toList(),
            ),
        ],
      ),
      body: Column(
        children: [
          // Context bar
          if (_isInitialized && _children.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue[50],
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Real-time data active • Watching tasks, points & patterns',
                      style: TextStyle(fontSize: 12, color: Colors.blue[800]),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _showQuickActions(),
                    icon: const Icon(Icons.bolt, size: 16),
                    label: const Text('Quick Help'),
                  ),
                ],
              ),
            ),
          
          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) {
                  return _buildTypingIndicator();
                }
                
                final message = _messages[index];
                final isUser = message['isUser'] ?? false;
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(14),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.85,
                    ),
                    decoration: BoxDecoration(
                      color: isUser 
                          ? Colors.blue[600] 
                          : message['isError'] == true 
                              ? Colors.red[100] 
                              : Colors.grey[100],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: isUser 
                      ? Text(
                          message['text'] ?? '',
                          style: const TextStyle(
                            color: Colors.white,
                            height: 1.4,
                            fontSize: 15,
                          ),
                        )
                      : MarkdownBody(
                          data: message['text'] ?? '',
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                              color: message['isError'] == true ? Colors.red[900] : Colors.black87,
                              height: 1.4,
                              fontSize: 15,
                            ),
                            strong: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                            blockquote: TextStyle(
                              color: Colors.grey[700],
                              fontStyle: FontStyle.italic,
                            ),
                            blockquoteDecoration: BoxDecoration(
                              border: Border(
                                left: BorderSide(color: Colors.blue[300]!, width: 4),
                              ),
                            ),
                          ),
                        ),
                  ),
                );
              },
            ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: _isInitialized 
                            ? 'Ask for negotiation advice...' 
                            : 'Initializing AI...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      enabled: _isInitialized && !_isTyping,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    mini: true,
                    onPressed: (_isInitialized && !_isTyping) ? _sendMessage : null,
                    backgroundColor: _isTyping ? Colors.grey : Colors.blue,
                    child: Icon(_isTyping ? Icons.hourglass_empty : Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Thinking...',
              style: TextStyle(color: Colors.grey[600], fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Quick Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.timer, color: Colors.blue),
                title: const Text('Screen time negotiation'),
                subtitle: const Text('Child wants more time'),
                onTap: () {
                  Navigator.pop(context);
                  _messageController.text = 'Child wants 30 more minutes. Should I approve?';
                  _sendMessage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.task_alt, color: Colors.green),
                title: const Text('Task motivation'),
                subtitle: const Text('Child refusing to do chores'),
                onTap: () {
                  Navigator.pop(context);
                  _messageController.text = 'How do I get them to complete their tasks?';
                  _sendMessage();
                },
              ),
              ListTile(
                leading: const Icon(Icons.analytics, color: Colors.purple),
                title: const Text('Analyze patterns'),
                subtitle: const Text('Deep behavioral analysis'),
                onTap: () async {
                  Navigator.pop(context);
                  setState(() => _isTyping = true);
                  final stream = await _aiService.analyzeChildPatterns();
                  _handleStreamingResponse(stream);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _aiService.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}