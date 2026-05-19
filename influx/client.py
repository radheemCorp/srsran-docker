import os
from dotenv import load_dotenv
from influxdb_client import InfluxDBClient

# Load variables from .env file
load_dotenv()

URL = os.getenv("INFLUXDB_URL")
TOKEN = os.getenv("INFLUXDB_TOKEN")

if not URL or not TOKEN:
    raise ValueError("Missing INFLUXDB_URL or INFLUXDB_TOKEN in .env file")

def get_influx_client(url: str, token: str) -> InfluxDBClient:
    """Initializes and returns the InfluxDB client."""
    return InfluxDBClient(url=url, token=token)

# ==========================================
#          ORGANIZATION MANAGEMENT
# ==========================================

def list_organizations(org_api):
    """Lists all organizations."""
    print("\n--- Organizations ---")
    try:
        orgs = org_api.find_organizations()
        if not orgs:
            print("No organizations found.")
            return
        for org in orgs:
            print(f"ID: {org.id} | Name: {org.name}")
    except Exception as e:
        print(f"[Error] Could not list organizations: {e}")


def create_organization(org_api, name: str):
    """Creates a new organization."""
    try:
        org = org_api.create_organization(name=name)
        print(f"\n[Success] Organization '{org.name}' created with ID: {org.id}")
        return org
    except Exception as e:
        print(f"\n[Error] Failed to create organization '{name}': {e}")


def delete_organization(org_api, org_id: str):
    """Deletes an organization by its ID."""
    try:
        org_api.delete_organization(org_id=org_id)
        print(f"\n[Success] Organization ID {org_id} deleted.")
    except Exception as e:
        print(f"\n[Error] Failed to delete organization ID {org_id}: {e}")


# ==========================================
#            BUCKET MANAGEMENT
# ==========================================

def list_buckets(buckets_api):
    """Lists all buckets."""
    print("\n--- Buckets ---")
    try:
        buckets_response = buckets_api.find_buckets()
        if not buckets_response or not buckets_response.buckets:
            print("No buckets found.")
            return
        for b in buckets_response.buckets:
            retention = b.retention_rules[0].every_seconds if b.retention_rules else 0
            print(f"ID: {b.id} | Name: {b.name} | Org ID: {b.org_id} | Retention: {retention}s")
    except Exception as e:
        print(f"[Error] Could not list buckets: {e}")


def create_bucket(buckets_api, bucket_name: str, org_id: str, retention_seconds: int = 0):
    """Creates a new bucket within a specific organization."""
    try:
        retention_rules = [{"type": "expire", "everySeconds": retention_seconds}] if retention_seconds > 0 else []
        bucket = buckets_api.create_bucket(bucket_name=bucket_name, org_id=org_id, retention_rules=retention_rules)
        print(f"\n[Success] Bucket '{bucket.name}' created with ID: {bucket.id}")
        return bucket
    except Exception as e:
        print(f"\n[Error] Failed to create bucket '{bucket_name}': {e}")


def delete_bucket(buckets_api, bucket_id: str):
    """Deletes a bucket by its ID."""
    try:
        buckets_api.delete_bucket(bucket_id)
        print(f"\n[Success] Bucket ID {bucket_id} deleted.")
    except Exception as e:
        print(f"\n[Error] Failed to delete bucket ID {bucket_id}: {e}")


# ==========================================
#                 MAIN EXECUTION
# ==========================================

if __name__ == "__main__":
    print(f"Connecting to InfluxDB at: {URL}")
    client = get_influx_client(URL, TOKEN)
    
    # InfluxDBClient manages the exact API imports dynamically
    orgs_api = client.organizations_api()
    buckets_api = client.buckets_api()

    try:
        # --- DEMO: Managing Organizations ---
        # list_organizations(orgs_api)
        # new_org = create_organization(orgs_api, "srsran")
        list_organizations(orgs_api)
        # resp = create_bucket(buckets_api, "srsran", "11b0b64d3752833a")
        # print(f"Created bucket with ID: {resp.id}")
        list_buckets(buckets_api)
        
    finally:
        client.close()