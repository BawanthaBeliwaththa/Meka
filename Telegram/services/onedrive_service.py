import os
import msal
import requests
import logging
from dotenv import load_dotenv

load_dotenv()
logger = logging.getLogger(__name__)

CLIENT_ID = os.getenv("ONEDRIVE_CLIENT_ID")
CLIENT_SECRET = os.getenv("ONEDRIVE_CLIENT_SECRET")
TENANT_ID = os.getenv("ONEDRIVE_TENANT_ID", "common")

AUTHORITY = f"https://login.microsoftonline.com/{TENANT_ID}"
SCOPES = ["Files.ReadWrite"]

class OneDriveService:
    def __init__(self):
        self.access_token = None
        self._app = None

    def _get_app(self):
        """Lazily initialize the MSAL app to avoid crash on import if env vars are missing."""
        if self._app is None:
            if not CLIENT_ID or not CLIENT_SECRET:
                logger.warning("OneDrive CLIENT_ID or CLIENT_SECRET not configured — OneDrive disabled.")
                return None
            self._app = msal.ConfidentialClientApplication(
                CLIENT_ID,
                authority=AUTHORITY,
                client_credential=CLIENT_SECRET,
            )
        return self._app

    def get_token(self):
        # In a real app with users, we'd use acquire_token_by_authorization_code
        # For a personal bot, acquire_token_for_client (if admin consent given) 
        # or acquire_token_by_username_password (deprecated but works for personal).
        # We will assume a daemon app structure using client credentials
        app = self._get_app()
        if not app:
            return None
        result = app.acquire_token_silent(SCOPES, account=None)
        if not result:
            logger.info("No token in cache, fetching new one from Azure AD.")
            result = app.acquire_token_for_client(scopes=SCOPES)
            
        if "access_token" in result:
            self.access_token = result["access_token"]
            return self.access_token
        else:
            logger.error(f"Failed to get OneDrive token: {result.get('error')} - {result.get('error_description')}")
            return None

    def upload_file(self, file_path: str, remote_folder: str = "MEKA_Captures"):
        """Uploads a local file to the user's OneDrive."""
        token = self.get_token()
        if not token:
            return False, "Not authenticated with OneDrive"

        if not os.path.exists(file_path):
            return False, f"File {file_path} not found"

        file_name = os.path.basename(file_path)
        
        # Microsoft Graph API endpoint for uploading a file
        # This uses the /me/drive/root:/ path. If using application permissions, we use /users/{user_id}/drive
        # For simplicity, we assume application permissions and write to a specific user drive or SharePoint site.
        # However, Graph API requires a user context to write to "my OneDrive".
        # If client credentials are used, we must specify the target user ID:
        ONEDRIVE_USER_ID = os.getenv("ONEDRIVE_USER_ID")
        if not ONEDRIVE_USER_ID:
            logger.error("ONEDRIVE_USER_ID is missing from .env")
            return False, "ONEDRIVE_USER_ID not configured"

        endpoint = f"https://graph.microsoft.com/v1.0/users/{ONEDRIVE_USER_ID}/drive/root:/{remote_folder}/{file_name}:/content"
        
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/octet-stream"
        }

        try:
            with open(file_path, "rb") as f:
                data = f.read()
                
            response = requests.put(endpoint, headers=headers, data=data)
            response.raise_for_status()
            logger.info(f"Successfully uploaded {file_name} to OneDrive/{remote_folder}")
            return True, response.json().get("webUrl", "Upload successful")
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to upload to OneDrive: {e}")
            if e.response is not None:
                logger.error(f"Graph API Error: {e.response.text}")
            return False, str(e)

onedrive_service = OneDriveService()
