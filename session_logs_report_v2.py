import firebase_admin
from firebase_admin import credentials, firestore
import csv
from collections import defaultdict

# Initialize
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("Fetching session logs from all users...\n")

# Fetch all users to get names
users_ref = db.collection("users").stream()
user_names = {}
for user in users_ref:
    data = user.to_dict()
    user_names[user.id] = data.get("username") or data.get("name") or data.get("email") or user.id[:8]

# Collect session logs from ALL users' subcollections
report_rows = []
summary_by_app = defaultdict(lambda: {"count": 0, "total_min": 0, "category": ""})
summary_by_child = defaultdict(lambda: {"total_min": 0, "verified": 0, "pending": 0, "rejected": 0})
summary_by_category = defaultdict(lambda: {"total_min": 0, "count": 0})

for user_id, user_name in user_names.items():
    logs = db.collection("users").document(user_id).collection("sessionLogs").stream()

    for log in logs:
        data = log.to_dict()

        app_name = data.get("appName", "Unknown")
        category = data.get("category", "Unknown")
        duration = data.get("durationMinutes", 0) or 0
        status = data.get("status", "unknown")
        child_id = data.get("childId", user_id)
        child_name = user_names.get(child_id, child_id[:8])
        parent_note = data.get("parentNote", "")
        points = data.get("pointsAwarded", 0)
        platform = data.get("platform", "unknown")

        # Handle timestamps
        created = data.get("createdAt")
        if created and hasattr(created, 'strftime'):
            date_str = created.strftime("%Y-%m-%d %H:%M")
        else:
            date_str = str(created) if created else "N/A"

        report_rows.append({
            "child_name": child_name,
            "app_name": app_name,
            "category": category,
            "duration_minutes": duration,
            "status": status,
            "points_awarded": points,
            "platform": platform,
            "parent_note": parent_note,
            "date": date_str
        })

        # Aggregations
        summary_by_app[app_name]["count"] += 1
        summary_by_app[app_name]["total_min"] += duration
        summary_by_app[app_name]["category"] = category

        summary_by_child[child_name]["total_min"] += duration
        summary_by_child[child_name][status] = summary_by_child[child_name].get(status, 0) + 1

        summary_by_category[category]["total_min"] += duration
        summary_by_category[category]["count"] += 1

# Save detailed report
with open("session_logs_detailed.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["child_name", "app_name", "category", "duration_minutes", "status", "points_awarded", "platform", "parent_note", "date"])
    writer.writeheader()
    writer.writerows(report_rows)

print(f"✅ Detailed report: session_logs_detailed.csv ({len(report_rows)} entries)")

# Save app summary
with open("app_usage_summary.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["App Name", "Times Logged", "Total Duration (min)", "Category"])
    for app, data in sorted(summary_by_app.items(), key=lambda x: x[1]["total_min"], reverse=True):
        writer.writerow([app, data["count"], data["total_min"], data["category"]])

print(f"✅ App summary: app_usage_summary.csv ({len(summary_by_app)} unique apps)")

# Save child summary
with open("child_usage_summary.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["Child Name", "Total Duration (min)", "Verified Logs", "Pending Logs", "Rejected Logs"])
    for child, data in sorted(summary_by_child.items(), key=lambda x: x[1]["total_min"], reverse=True):
        writer.writerow([child, data["total_min"], data.get("verified", 0), data.get("pending", 0), data.get("rejected", 0)])

print(f"✅ Child summary: child_usage_summary.csv ({len(summary_by_child)} children)")

# Print preview
print("\n" + "="*50)
print("QUICK PREVIEW")
print("="*50)

print("\n--- Top 10 Most Used Apps ---")
for app, data in sorted(summary_by_app.items(), key=lambda x: x[1]["total_min"], reverse=True)[:10]:
    print(f"  {app}: {data['count']} logs, {data['total_min']} min total ({data['category']})")

print("\n--- By Category ---")
for cat, data in sorted(summary_by_category.items(), key=lambda x: x[1]["total_min"], reverse=True):
    print(f"  {cat}: {data['count']} logs, {data['total_min']} min total")

print("\n--- By Child ---")
for child, data in sorted(summary_by_child.items(), key=lambda x: x[1]["total_min"], reverse=True):
    print(f"  {child}: {data['total_min']} min total (verified: {data.get('verified', 0)}, pending: {data.get('pending', 0)})")

print("\n" + "="*50)
print("All CSV files are ready to open in Excel.")
print("="*50)
