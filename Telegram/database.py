import aiosqlite
import os
from datetime import datetime

DB_PATH = 'data/meka_bot.db'

async def init_db():
    os.makedirs('data', exist_ok=True)
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute('''
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY,
                username TEXT,
                role TEXT DEFAULT 'pending',
                command_count INTEGER DEFAULT 0,
                is_paid BOOLEAN DEFAULT 0
            )
        ''')
        for col in [
            "age INTEGER", 
            "gender TEXT", 
            "name TEXT", 
            "email TEXT",
            "daily_count INTEGER DEFAULT 0", 
            "weekly_count INTEGER DEFAULT 0", 
            "last_command_date TEXT", 
            "last_command_week INTEGER"
        ]:
            try:
                await db.execute(f"ALTER TABLE users ADD COLUMN {col}")
            except:
                pass
        await db.commit()

async def set_user_email(user_id: int, email: str):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute('UPDATE users SET email = ? WHERE id = ?', (email.strip().lower(), user_id))
        await db.commit()

async def set_onboarding_data(user_id: int, name: str, gender: str):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute('UPDATE users SET name = ?, gender = ? WHERE id = ?', (name, gender, user_id))
        await db.commit()

async def get_user(user_id: int):
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute('SELECT * FROM users WHERE id = ?', (user_id,)) as cursor:
            return await cursor.fetchone()

async def add_user(user_id: int, username: str):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute(
            'INSERT OR IGNORE INTO users (id, username, role) VALUES (?, ?, ?)',
            (user_id, username, 'pending')
        )
        await db.commit()

async def set_role(user_id: int, role: str):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute('UPDATE users SET role = ? WHERE id = ?', (role, user_id))
        await db.commit()

async def set_paid(user_id: int, is_paid: bool):
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute('UPDATE users SET is_paid = ? WHERE id = ?', (is_paid, user_id))
        await db.commit()

async def increment_command_count(user_id: int):
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute('SELECT * FROM users WHERE id = ?', (user_id,)) as cursor:
            user = await cursor.fetchone()
            
        if not user:
            return
            
        now = datetime.now()
        current_date = now.strftime('%Y-%m-%d')
        current_week = now.isocalendar()[1]
        
        daily_count = user['daily_count'] if user['daily_count'] is not None else 0
        weekly_count = user['weekly_count'] if user['weekly_count'] is not None else 0
        
        if user['last_command_date'] != current_date:
            daily_count = 0
            
        if user['last_command_week'] != current_week:
            weekly_count = 0
            
        daily_count += 1
        weekly_count += 1
        
        await db.execute('''
            UPDATE users SET 
            command_count = command_count + 1,
            daily_count = ?,
            weekly_count = ?,
            last_command_date = ?,
            last_command_week = ?
            WHERE id = ?
        ''', (daily_count, weekly_count, current_date, current_week, user_id))
        await db.commit()

async def get_all_users():
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        async with db.execute('SELECT * FROM users') as cursor:
            return await cursor.fetchall()
