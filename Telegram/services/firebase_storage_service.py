import os
import uuid
import logging
from firebase_admin import storage
from services.esp32_service import _get_firebase_app

logger = logging.getLogger(__name__)

class FirebaseStorageService:
    def upload_file(self, file_path: str, remote_folder: str = "MEKA_Captures"):
        """Uploads a local file to Firebase Storage and returns the public download URL."""
        _get_firebase_app()
        if not os.path.exists(file_path):
            return False, f"File {file_path} not found"

        file_name = os.path.basename(file_path)
        blob_name = f"{remote_folder}/{uuid.uuid4()}_{file_name}"
        
        try:
            bucket = storage.bucket()
            blob = bucket.blob(blob_name)
            
            # Upload the file
            blob.upload_from_filename(file_path)
            
            # Make the blob publicly viewable
            blob.make_public()
            public_url = blob.public_url
            
            logger.info(f"Successfully uploaded {file_name} to Firebase Storage")
            return True, public_url
        except Exception as e:
            logger.error(f"Failed to upload to Firebase Storage: {e}")
            return False, str(e)

firebase_storage_service = FirebaseStorageService()
