class TaskTemplate {
  final String name;
  final int points;
  final String description;
  final bool requiresApproval;
  final bool requiresPhoto;

  const TaskTemplate({
    required this.name,
    required this.points,
    required this.description,
    this.requiresApproval = true,
    this.requiresPhoto = false,
  });
}

const List<TaskTemplate> predefinedTasks = [
  TaskTemplate(
    name: 'No screens before 10 AM on Saturday',
    points: 10,
    description: 'Because morning sunlight helps your body clock work better and makes you feel more awake.',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Keep devices in the basket during dinner',
    points: 15,
    description: 'Because talking with family helps you feel connected and teaches you manners.',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Spend 30 minutes outside playing instead of tablet/iPad time',
    points: 8,
    description: 'Because sunlight and movement help you sleep better and earn bonus screen time later.',
    requiresApproval: false,
    requiresPhoto: true,
  ),
  TaskTemplate(
    name: 'Build with LEGO or draw for 45 minutes instead of watching YouTube',
    points: 7,
    description: 'Because creating things makes you feel proud in a way that just watching cannot.',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Complete your homework and chores before turning on the TV',
    points: 10,
    description: 'Because finishing responsibilities first makes screen time feel like a real reward, not an escape.',
    requiresApproval: false,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Lead a family board game tonight instead of playing Roblox',
    points: 5,
    description: 'Because creating fun memories together makes everyone happier than sitting in separate rooms.',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Turn off your screen devices completely before bedtime',
    points: 5,
    description: 'Because even sleep mode emits small signals that disturb deep sleep.',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Stand up and stretch every time an episode ends',
    points: 20,
    description: 'Because your back and neck get stiff when you sit still too long.',
    requiresApproval: true,
    requiresPhoto: true,
  ),
];