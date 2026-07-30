import os
from dotenv import load_dotenv
from azure.storage.blob import BlobServiceClient
from pathlib import Path

load_dotenv()

location = Path(__file__).resolve().parent

project_root = location

ACCOUNT_KEY=os.getenv("ACCOUNT_KEY")
ACCOUNT_NAME = "311servicestorage"
CONTAINER_NAME = "bronze"

LOCAL_FILE_PATH = project_root / "data" / "urban_service_requests.csv"

BLOB_NAME = "urban_service_requests.csv"

def upload_data():
    """
    Uploads data directly from the local file or the API into the Azure blob container
    """
    try:
        # Initialize the Azure blob service 
        blob_service_client = BlobServiceClient(
             account_url=f"https://{ACCOUNT_NAME}.blob.core.windows.net",
             credential=ACCOUNT_KEY
        ) 

        # Retrieve the blob client 
        blob_client = blob_service_client.get_blob_client(container=CONTAINER_NAME, blob=BLOB_NAME)

        print(f'starting file upload from {LOCAL_FILE_PATH}')

        # Open the local file or API data and upload to the blob while overwriting existing data
        with open(LOCAL_FILE_PATH, 'rb') as data:
            blob_client.upload_blob(
                data,
                overwrite=True,
                max_concurrency=4
            )

            print(f'upload successful. File loaded to {CONTAINER_NAME}')

    except Exception as e:
        print(e)

    return None