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
  // Health
  RewardTemplate(
    name: "Choose the Family Adventure",
    category: "Health",
    pointCost: 50,
    description: "Pick Saturday's physical activity (hiking trail, bike ride destination, or swimming pool)",
  ),
  RewardTemplate(
    name: "Choose excercise",
    category: "Health",
    pointCost: 80,
    description: "Pick an exercise for family",
  ),
  
  // Education
  RewardTemplate(
    name: "Art supplies",
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
  
  // Family
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
  
  // Food
  RewardTemplate(
    name: "Choose Dinner",
    category: "Family",
    pointCost: 60,
    description: "Pick tonight's family dinner menu",
  ),
  RewardTemplate(
    name: "Extra Dessert",
    category: "Family",
    pointCost: 70,
    description: "Get an extra dessert after dinner",
  ),
  
// Money
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

  // Screen
  RewardTemplate(
    name: "1 Hour Movie Night Choice",
    category: "Screen Time",
    pointCost: 30,
    description: "Pick a movie for family movie night",
  ),
  RewardTemplate(
    name: "Use phone for extra 15 minutes today",
    category: "Screen Time",
    pointCost: 120,
    description: "Use phone for extra 15 minutes today",
  ),
];