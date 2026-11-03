import firebase_admin
from firebase_admin import credentials, firestore
import json

# Initialize
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("=== ALL COLLECTIONS IN YOUR DATABASE ===\n")

# List all top-level collections
collections = db.collections()
for col in collections:
    name = col.id
    docs = list(col.limit(1).stream())
    count = len(list(col.stream()))

    print(f"Collection: '{name}'")
    print(f"  Document count: {count}")

    if docs:
        sample = docs[0].to_dict()
        # Convert timestamps to strings for display
        clean_sample = {}
        for k, v in sample.items():
            if hasattr(v, 'strftime'):
                clean_sample[k] = v.strftime("%Y-%m-%d %H:%M:%S")
            elif isinstance(v, list) and len(v) > 3:
                clean_sample[k] = v[:3] + [f"... ({len(v)} total)"]
            else:
                clean_sample[k] = v

        print(f"  Fields: {list(clean_sample.keys())}")
        print(f"  Sample doc: {json.dumps(clean_sample, indent=2, default=str)[:500]}...")
    else:
        print(f"  (empty collection)")
    print()

print("\n=== LOOK FOR ===")
print("A collection that has fields like: childId, appsUsed, appName, usage, duration, screenTime, category, educational, entertainment")
print("\nOnce you find the right collection name, tell me and I'll generate the correct report.")
