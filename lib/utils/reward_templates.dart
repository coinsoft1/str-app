// Predefined rewards for quick selection
class RewardTemplate {
  final String name;
  final String category;
  final int pointCost;
  final String description;

  const RewardTemplate({
    required this.name,
    required this.category,
    required this.pointCost,
    required this.description,
  });
}

const List<RewardTemplate> predefinedRewards = [
  // Screen Time
  RewardTemplate(
    name: "30 Minutes Extra Screen Time",
    category: "Screen Time",
    pointCost: 50,
    description: "Watch videos or play games for 30 extra minutes",
  ),
  RewardTemplate(
    name: "1 Hour Movie Night Choice",
    category: "Screen Time",
    pointCost: 80,
    description: "Pick a movie for family movie night",
  ),
  
  // Education
  RewardTemplate(
    name: "New Book",
    category: "Education",
    pointCost: 100,
    description: "Choose a new book from the bookstore",
  ),
  RewardTemplate(
    name: "Science Kit",
    category: "Education",
    pointCost: 200,
    description: "Get a new science experiment kit",
  ),
  
  // Social
  RewardTemplate(
    name: "Friend Sleepover",
    category: "Social",
    pointCost: 150,
    description: "Invite a friend for a sleepover this weekend",
  ),
  RewardTemplate(
    name: "Trip to Park",
    category: "Social",
    pointCost: 40,
    description: "Go to the playground with friends",
  ),
  
  // Family
  RewardTemplate(
    name: "Choose Dinner",
    category: "Family",
    pointCost: 60,
    description: "Pick tonight's family dinner menu",
  ),
  RewardTemplate(
    name: "Game Night Choice",
    category: "Family",
    pointCost: 70,
    description: "Select the family board game for tonight",
  ),
  
  // Health & Activities
  RewardTemplate(
    name: "Extra Dessert",
    category: "Health",
    pointCost: 30,
    description: "Get an extra dessert after dinner",
  ),
  RewardTemplate(
    name: "Skip Chore Day",
    category: "Activities",
    pointCost: 120,
    description: "Skip one day of chores this week",
  ),
];