import firebase_admin
from firebase_admin import credentials, firestore
import json
import pandas as pd

# Initialize
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

def export_collection(collection_name, output_file):
    docs = db.collection(collection_name).stream()
    data = []
    for doc in docs:
        item = doc.to_dict()
        item['id'] = doc.id
        data.append(item)

    # Save as JSON
    with open(f"{output_file}.json", "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, default=str)

    # Save as CSV (flattened)
    if data:
        df = pd.json_normalize(data)
        df.to_csv(f"{output_file}.csv", index=False)

    print(f"Exported {len(data)} documents from '{collection_name}'")

# Export your main collections
export_collection("users", "users_export")
export_collection("families", "families_export")
export_collection("tasks", "tasks_export")
export_collection("rewards", "rewards_export")
export_collection("children", "children_export")
export_collection("notifications", "notifications_export")
export_collection("sessionLogs", "sessionLogs_export")

print("\nDone! Check your folder for .json and .csv files.")
