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
    name: 'Use phone for 30minutes today',
    points: 10,
    description: 'Use phone for only 30minutes today to be able to use it for upcoming days',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Do Homework',
    points: 15,
    description: 'Complete all homework for the day',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Walk the Dog',
    points: 8,
    description: 'Take dog for 20-minute walk',
    requiresApproval: false,
    requiresPhoto: true,
  ),
  TaskTemplate(
    name: 'Wash Dishes',
    points: 7,
    description: 'Load/unload dishwasher and clean sink',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Read for 30 Minutes',
    points: 10,
    description: 'Read any book for at least 30 minutes',
    requiresApproval: false,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Help with Groceries',
    points: 5,
    description: 'Help carry and put away groceries',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Take Out Trash',
    points: 5,
    description: 'Empty all trash bins and take to curb',
    requiresApproval: true,
    requiresPhoto: false,
  ),
  TaskTemplate(
    name: 'Yard Work',
    points: 20,
    description: 'Mow lawn, rake leaves, or water plants',
    requiresApproval: true,
    requiresPhoto: true,
  ),
];