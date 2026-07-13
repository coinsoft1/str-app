// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/settings_service.dart';
import 'widgets/onboarding_screen.dart';
import 'screens/login_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/parent_dashboard.dart';
import 'screens/child_dashboard.dart';
import 'screens/create_task.dart';
import 'screens/ai_bot_screen.dart';
import 'screens/task_screen.dart';
import 'screens/parent/reward_management_screen.dart';
import 'screens/parent/admin_review_screen.dart';
import 'screens/parent/analytics_dashboard.dart';
import 'screens/parent/verification_settings_screen.dart';
import 'screens/parent/verification_queue_screen.dart';
import 'screens/parent/goal_creation_screen.dart';
import 'screens/parent/parent_goals_screen.dart';
import 'screens/parent/wheel_config_screen.dart';
import 'screens/parent/approve_tasks_screen.dart';
import 'screens/parent/goal_history_screen.dart';
import 'screens/usage_verification_screen.dart';
import 'screens/usage_analytics_screen.dart';
import 'screens/child/redeem_rewards_screen.dart';
import 'screens/child/session_logging_screen.dart';
import 'screens/child/goal_review_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const STRApp());
}

class STRApp extends StatelessWidget {
  const STRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        return MaterialApp(
          title: 'STR App',
          debugShowCheckedModeBanner: false,
          theme: settings.themeData,
          darkTheme: settings.darkThemeData,
          themeMode: settings.effectiveThemeMode,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaleFactor: settings.fontScale),
              child: child!,
            );
          },
          home: const AuthWrapper(),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/role_selection': (context) => const RoleSelectionScreen(),
            '/parent_dashboard': (context) => const ParentDashboard(),
            '/child_dashboard': (context) => const ChildDashboard(),
            '/create_task': (context) => const CreateTaskScreen(),
            '/ai_bot': (context) => const AIBotScreen(),
            '/tasks': (context) => const TaskScreen(),
            '/reward_management': (context) => const RewardManagementScreen(),
            '/admin_review': (context) => const AdminReviewScreen(),
            '/analytics': (context) => const AnalyticsDashboard(),
            '/verification_settings': (context) => const VerificationSettingsScreen(),
            '/verification_queue': (context) => const VerificationQueueScreen(),
            '/goal_creation': (context) => const GoalCreationScreen(),
            '/parent_goals': (context) => const ParentGoalsScreen(),
            '/wheel_config': (context) => const WheelConfigScreen(),
            '/approve_tasks': (context) => const ApproveTasksScreen(),
            '/goal_history': (context) => const GoalHistoryScreen(),
            '/usage_verification': (context) => const UsageVerificationScreen(),
            '/usage_analytics': (context) => UsageAnalyticsScreen(childId: '', childName: ''),
            '/redeem_rewards': (context) => const RedeemRewardsScreen(),
            '/session_logging': (context) => const SessionLoggingScreen(),
            '/goal_review': (context) => const GoalReviewScreen(),
          },
        );
      },
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                final role = userData?['role'] as String?;
                final hasSeenOnboarding = userData?['hasSeenOnboarding'] == true;

                if (!hasSeenOnboarding) {
                  if (role == 'parent') {
                    return _buildParentOnboarding(context, user.uid);
                  } else if (role == 'child') {
                    return _buildChildOnboarding(context, user.uid);
                  }
                }

                if (role == 'parent') {
                  return const ParentDashboard();
                } else if (role == 'child') {
                  return const ChildDashboard();
                }
              }

              return const LoginScreen();
            },
          );
        }

        return const LoginScreen();
      },
    );
  }

  Widget _buildParentOnboarding(BuildContext context, String uid) {
    return OnboardingScreen(
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
        ),
        OnboardingPage(
          title: 'Stay Notified',
          description: 'Get instant alerts when your child completes tasks, redeems rewards, or wins bonus spins on the reward wheel.',
          icon: Icons.notifications,
          color: Colors.green,
        ),
      ],
      onComplete: () => _finishOnboarding(uid, '/parent_dashboard', context),
      onSkip: () => _finishOnboarding(uid, '/parent_dashboard', context),
      completeButtonText: 'Go to Dashboard',
    );
  }

  Widget _buildChildOnboarding(BuildContext context, String uid) {
    return OnboardingScreen(
      pages: [
        OnboardingPage(
          title: 'Log Time',
          description: 'Track your daily screen time usage honestly to earn points.',
          icon: Icons.timer,
          color: Colors.blue,
        ),
        OnboardingPage(
          title: 'Tasks',
          description: 'Complete tasks assigned by your parent to earn rewards.',
          icon: Icons.checklist,
          color: Colors.green,
        ),
        OnboardingPage(
          title: 'Wheel',
          description: 'Spin the reward wheel for a chance to win bonus points!',
          icon: Icons.casino,
          color: Colors.purple,
        ),
        OnboardingPage(
          title: 'Rewards',
          description: 'Redeem your points for exciting rewards from your parent.',
          icon: Icons.card_giftcard,
          color: Colors.amber,
        ),
      ],
      onComplete: () => _finishOnboarding(uid, '/child_dashboard', context),
      onSkip: () => _finishOnboarding(uid, '/child_dashboard', context),
      completeButtonText: 'Get Started',
    );
  }

  void _finishOnboarding(String uid, String route, BuildContext context) {
    FirebaseFirestore.instance.collection('users').doc(uid).update({'hasSeenOnboarding': true});
    // AuthWrapper StreamBuilder will auto-rebuild when user doc updates
  }
}