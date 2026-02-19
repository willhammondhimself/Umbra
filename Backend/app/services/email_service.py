import logging
from email.message import EmailMessage

import aiosmtplib

from app.config import settings

logger = logging.getLogger(__name__)


async def send_email(to: str, subject: str, body_html: str) -> bool:
    """Send an email via SMTP. Returns True on success."""
    if not settings.SMTP_HOST:
        logger.warning("SMTP not configured — email not sent to %s", to)
        return False

    message = EmailMessage()
    message["From"] = settings.SMTP_FROM_EMAIL
    message["To"] = to
    message["Subject"] = subject
    message.set_content(body_html, subtype="html")

    try:
        await aiosmtplib.send(
            message,
            hostname=settings.SMTP_HOST,
            port=settings.SMTP_PORT,
            username=settings.SMTP_USERNAME or None,
            password=settings.SMTP_PASSWORD or None,
            start_tls=True,
        )
        return True
    except Exception:
        logger.exception("Failed to send email to %s", to)
        return False


async def send_verification_email(to: str, token: str) -> bool:
    """Send email verification link."""
    link = f"{settings.FRONTEND_URL}/verify-email?token={token}"
    html = f"""
    <h2>Welcome to Tether!</h2>
    <p>Please verify your email address by clicking the link below:</p>
    <p><a href="{link}">Verify Email</a></p>
    <p>This link expires in 24 hours.</p>
    <p>If you didn't create an account, you can ignore this email.</p>
    """
    return await send_email(to, "Verify your Tether email", html)


async def send_password_reset_email(to: str, token: str) -> bool:
    """Send password reset link."""
    link = f"{settings.FRONTEND_URL}/reset-password?token={token}"
    html = f"""
    <h2>Reset your Tether password</h2>
    <p>Click the link below to reset your password:</p>
    <p><a href="{link}">Reset Password</a></p>
    <p>This link expires in 1 hour.</p>
    <p>If you didn't request this, you can ignore this email.</p>
    """
    return await send_email(to, "Reset your Tether password", html)
