# Telegram/services/email_service.py — Admin Email Notification Service
import os
import smtplib
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime

logger = logging.getLogger(__name__)

# Config from environment
SMTP_SERVER = os.getenv("SMTP_SERVER", "smtp.gmail.com")
SMTP_PORT   = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER   = os.getenv("SMTP_USER", "")
SMTP_PASS   = os.getenv("SMTP_PASS", "")
DEFAULT_ADMIN_EMAIL = "bawanthabeliwaththa@gmail.com"

async def send_admin_login_notification(user_name: str, user_email: str, is_new_user: bool = False, admin_emails: list = None):
    """
    Dispatches an email notification to all admins when a user logs in / registers.
    """
    if not admin_emails:
        admin_emails = [DEFAULT_ADMIN_EMAIL]
    
    if not SMTP_USER or not SMTP_PASS:
        logger.info(f"📧 [Email Event] User login: Name='{user_name}', Email='{user_email}', New={is_new_user}. (Configure SMTP_USER & SMTP_PASS in .env to send live emails)")
        return

    subject = f"🔔 MEKA Notification: New User Login - {user_name}" if is_new_user else f"🔑 MEKA Notification: User Login - {user_name}"
    login_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S UTC")

    body = f"""
    <html>
      <body style="font-family: Arial, sans-serif; background-color: #0f172a; color: #f8fafc; padding: 20px;">
        <div style="max-width: 500px; margin: 0 auto; background: #1e293b; border: 1px solid #38bdf8; border-radius: 16px; padding: 24px;">
          <h2 style="color: #38bdf8; margin-top: 0;">🤖 MEKA System Security Alert</h2>
          <p style="font-size: 15px; color: #cbd5e1;">A user has logged into the MEKA Web Application.</p>
          
          <table style="width: 100%; border-collapse: collapse; margin: 16px 0;">
            <tr style="border-bottom: 1px solid #334155;">
              <td style="padding: 8px 0; color: #94a3b8; font-weight: bold;">User Name:</td>
              <td style="padding: 8px 0; color: #f8fafc; text-align: right;">{user_name}</td>
            </tr>
            <tr style="border-bottom: 1px solid #334155;">
              <td style="padding: 8px 0; color: #94a3b8; font-weight: bold;">User Email:</td>
              <td style="padding: 8px 0; color: #38bdf8; text-align: right;">{user_email}</td>
            </tr>
            <tr style="border-bottom: 1px solid #334155;">
              <td style="padding: 8px 0; color: #94a3b8; font-weight: bold;">Account Status:</td>
              <td style="padding: 8px 0; color: {'#10b981' if is_new_user else '#38bdf8'}; text-align: right; font-weight: bold;">
                {'New Registration' if is_new_user else 'Existing User Sign-In'}
              </td>
            </tr>
            <tr>
              <td style="padding: 8px 0; color: #94a3b8; font-weight: bold;">Timestamp:</td>
              <td style="padding: 8px 0; color: #f8fafc; text-align: right;">{login_time}</td>
            </tr>
          </table>

          <div style="text-align: center; margin-top: 20px; font-size: 12px; color: #64748b;">
            This is an automated notification from your MEKA Cybernetic Intelligence Node.
          </div>
        </div>
      </body>
    </html>
    """

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"]    = f"MEKA Bot <{SMTP_USER}>"
    msg["To"]      = ", ".join(admin_emails)
    msg.attach(MIMEText(body, "html"))

    try:
        with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.sendmail(SMTP_USER, admin_emails, msg.as_string())
        logger.info(f"✉️ Email notification sent to admins ({admin_emails}) for user {user_email}")
    except Exception as e:
        logger.error(f"❌ Failed to send login email notification: {e}")
