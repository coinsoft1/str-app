import firebase_admin
from firebase_admin import credentials, firestore
import json

# Initialize
cred = credentials.Certificate("service-account.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

print("=== SEARCHING FOR SUBCOLLECTIONS ===\n")

# Check subcollections under users
top_collections = ["users", "families"]

for top_col_name in top_collections:
    print(f"--- Checking '{top_col_name}' documents for subcollections ---")
    docs = list(db.collection(top_col_name).limit(5).stream())

    if not docs:
        print(f"  No documents found in '{top_col_name}'")
        continue

    for doc in docs:
        doc_id = doc.id
        subcollections = list(doc.reference.collections())

        if subcollections:
            print(f"\n  Document: {doc_id}")
            for sub in subcollections:
                sub_name = sub.id
                sub_docs = list(sub.limit(1).stream())
                print(f"    → Subcollection: '{sub_name}'")

                if sub_docs:
                    sample = sub_docs[0].to_dict()
                    clean = {}
                    for k, v in sample.items():
                        if hasattr(v, 'strftime'):
                            clean[k] = v.strftime("%Y-%m-%d %H:%M:%S")
                        elif isinstance(v, list) and len(v) > 3:
                            clean[k] = v[:3] + [f"... ({len(v)} total)"]
                        else:
                            clean[k] = v
                    print(f"      Fields: {list(clean.keys())}")
                    print(f"      Sample: {json.dumps(clean, indent=2, default=str)[:600]}")
                else:
                    print(f"      (empty subcollection)")
        else:
            print(f"  Document {doc_id}: no subcollections")
    print()

print("\n=== ALSO CHECKING ALL TOP-LEVEL COLLECTIONS FOR 'session' OR 'usage' ===")
all_cols = db.collections()
for col in all_cols:
    name = col.id.lower()
    if "session" in name or "usage" in name or "log" in name or "screen" in name or "time" in name:
        count = len(list(col.stream()))
        print(f"  FOUND: '{col.id}' ({count} documents)")
