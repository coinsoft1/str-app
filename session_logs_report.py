import firebase_admin
from firebase_admin import credentials, firestore
import csv
from datetime import datetime

# Initialize
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def get_child_name(child_id):
    """Look up child name from users collection"""
    try:
        doc = db.collection("users").document(child_id).get()
        if doc.exists:
            data = doc.to_dict()
            return data.get("username") or data.get("name") or child_id[:8]
    except:
        pass
    return child_id[:8]

# Fetch all session logs
print("Fetching session logs...")
logs = db.collection("sessionLogs").stream()

# Prepare data
report_rows = []
summary = {}  # app_name -> {count, total_duration, category}

for log in logs:
    data = log.to_dict()
    child_id = data.get("childId", "")
    child_name = get_child_name(child_id)
    apps = data.get("appsUsed", [])
    category = data.get("category", "unknown")
    duration = data.get("duration", 0)
    status = data.get("status", "pending")
    created = data.get("createdAt")

    # Handle Firestore timestamp
    if created:
        date_str = created.strftime("%Y-%m-%d %H:%M") if hasattr(created, 'strftime') else str(created)
    else:
        date_str = "N/A"

    # Each app in the session gets its own row
    if isinstance(apps, list) and apps:
        for app in apps:
            report_rows.append({
                "child_name": child_name,
                "app_name": app,
                "category": category,
                "duration_minutes": duration,
                "status": status,
                "date": date_str
            })

            # Summary
            if app not in summary:
                summary[app] = {"count": 0, "total_duration": 0, "category": category}
            summary[app]["count"] += 1
            summary[app]["total_duration"] += duration
    else:
        # Single app or no apps listed
        app_name = apps if isinstance(apps, str) else "Unknown"
        report_rows.append({
            "child_name": child_name,
            "app_name": app_name,
            "category": category,
            "duration_minutes": duration,
            "status": status,
            "date": date_str
        })

# Save detailed report
with open("session_logs_report.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=["child_name", "app_name", "category", "duration_minutes", "status", "date"])
    writer.writeheader()
    writer.writerows(report_rows)

print(f"\n✅ Detailed report saved: session_logs_report.csv ({len(report_rows)} entries)")

# Save summary report
with open("app_usage_summary.csv", "w", newline="", encoding="utf-8") as f:
    writer = csv.writer(f)
    writer.writerow(["App Name", "Times Logged", "Total Duration (min)", "Category"])
    for app, data in sorted(summary.items(), key=lambda x: x[1]["total_duration"], reverse=True):
        writer.writerow([app, data["count"], data["total_duration"], data["category"]])

print(f"✅ Summary report saved: app_usage_summary.csv ({len(summary)} unique apps)")

# Print quick preview
print("\n--- Top 10 Most Used Apps ---")
for app, data in sorted(summary.items(), key=lambda x: x[1]["total_duration"], reverse=True)[:10]:
    print(f"  {app}: {data['count']} sessions, {data['total_duration']} min total")

print("\n--- By Category ---")
edu_time = sum(d["total_duration"] for app, d in summary.items() if d["category"].lower() == "educational")
ent_time = sum(d["total_duration"] for app, d in summary.items() if d["category"].lower() == "entertainment")
print(f"  Educational: {edu_time} minutes")
print(f"  Entertainment: {ent_time} minutes")
