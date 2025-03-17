import logging
import random
import sqlite3
from aiogram import Bot, Dispatcher, types
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.utils import executor
from datetime import datetime
import asyncio
from forbidden_words import FORBIDDEN_WORDS
import time

# Токен бота
API_TOKEN = '-'

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
dp = Dispatcher(bot)

CAPTCHA_TIMEOUT = 120  # Время на решение капчи (в секундах)
user_data = {}  # Хранение данных о капче для каждого пользователя
emoji_buttons = {
    '🍎': 'Яблоко',
    '🍕': 'Пицца',
    '🍐': 'Груша',
    '🍔': 'Гамбургер',
    '🍟': 'Картошка фри',
    '🌭': 'Хот-дог',
    '🍿': 'Попкорн',
    '🍩': 'Пончик',
    '🍪': 'Печенье',
    '🍫': 'Шоколад',
    '🍭': 'Леденец',
    '🥤': 'Кола',
    '🥨': 'Соленые палочки',
    '💡': 'Лампочка',  # Добавляем лампочку
}

# Инициализация базы данных group_members
def init_group_db():
    try:
        conn = sqlite3.connect('group_members.db')
        cursor = conn.cursor()
        cursor.execute('''  
            CREATE TABLE IF NOT EXISTS group_members (
                group_id INTEGER,
                user_id INTEGER,
                PRIMARY KEY (group_id, user_id)
            )
        ''')
        conn.commit()
        conn.close()
        logging.info("База данных group_members.db успешно инициализирована.")
    except Exception as e:
        logging.error(f"Ошибка при инициализации базы данных group_members: {e}")

# Инициализация базы данных good_users
def init_good_users_db():
    try:
        conn = sqlite3.connect('good_users.db')
        cursor = conn.cursor()
        cursor.execute('''  
            CREATE TABLE IF NOT EXISTS good_users (
                group_id INTEGER,
                user_id INTEGER,
                PRIMARY KEY (group_id, user_id)
            )
        ''')
        conn.commit()
        conn.close()
        logging.info("База данных good_users.db успешно инициализирована.")
    except Exception as e:
        logging.error(f"Ошибка при инициализации базы данных good_users: {e}")

# Добавление пользователя в базу данных group_members
def add_user_to_db(group_id, user_id):
    try:
        conn = sqlite3.connect('group_members.db')
        cursor = conn.cursor()
        cursor.execute('''  
            INSERT OR IGNORE INTO group_members (group_id, user_id)
            VALUES (?, ?)
        ''', (group_id, user_id))
        conn.commit()
        conn.close()
        logging.info(f"Пользователь {user_id} успешно добавлен в базу данных group_members.")
    except Exception as e:
        logging.error(f"Ошибка при добавлении пользователя в базу данных group_members: {e}")

# Добавление пользователя в базу данных good_users
def add_good_user_to_db(group_id, user_id):
    try:
        conn = sqlite3.connect('good_users.db')
        cursor = conn.cursor()
        cursor.execute('''  
            INSERT OR IGNORE INTO good_users (group_id, user_id)
            VALUES (?, ?)
        ''', (group_id, user_id))
        conn.commit()
        conn.close()
        logging.info(f"Пользователь {user_id} успешно добавлен в базу данных good_users.")
    except Exception as e:
        logging.error(f"Ошибка при добавлении пользователя в базу данных good_users: {e}")

# Проверка, находится ли пользователь в базе данных group_members
def is_user_in_group_db(group_id, user_id):
    try:
        conn = sqlite3.connect('group_members.db')
        cursor = conn.cursor()
        cursor.execute('''  
            SELECT * FROM group_members WHERE group_id = ? AND user_id = ?
        ''', (group_id, user_id))
        result = cursor.fetchone()
        conn.close()
        return result is not None
    except Exception as e:
        logging.error(f"Ошибка при проверке пользователя в базе данных group_members: {e}")
        return False

# Проверка, находится ли пользователь в базе данных good_users
def is_user_in_good_users_db(group_id, user_id):
    try:
        conn = sqlite3.connect('good_users.db')
        cursor = conn.cursor()
        cursor.execute('''  
            SELECT * FROM good_users WHERE group_id = ? AND user_id = ?
        ''', (group_id, user_id))
        result = cursor.fetchone()
        conn.close()
        return result is not None
    except Exception as e:
        logging.error(f"Ошибка при проверке пользователя в базе данных good_users: {e}")
        return False

# Функция логирования действий в группе
def log_group_activity(action, user=None, chat=None, message=None):
    timestamp = datetime.now().strftime("%d.%m.%Y %H:%M")

    # Логирование сообщения
    if message:
        log_message = f"{timestamp} - {action}: {user} написал сообщение '{message}' в чате {chat}"
    # Логирование действий
    elif user and chat:
        log_message = f"{timestamp} - {action}: {user} в чате {chat}"
    else:
        log_message = f"{timestamp} - {action}"

    # Запись в лог
    logging.info(log_message)

# Функция для перемешивания кнопок капчи
def get_random_keyboard():
    keyboard = InlineKeyboardMarkup(row_width=3)
    buttons = [InlineKeyboardButton(text=emoji, callback_data=emoji) for emoji in emoji_buttons.keys()]
    random.shuffle(buttons)
    keyboard.add(*buttons)
    return keyboard

# Функция для проверки наличия запрещенных слов в сообщении
import re
from fuzzywuzzy import fuzz

def contains_forbidden_words(message_text):
    # Функция для нормализации текста
    def normalize_text(text):
        # Словарь замен латинских символов на кириллические
        replacements = {
            'a': 'а',
            'b': 'б',
            'c': 'ц',
            'd': 'д',
            'e': 'е',
            'f': 'ф',
            'g': 'г',
            'h': 'х',
            'i': 'и',
            'j': 'й',
            'k': 'к',
            'l': 'л',
            'm': 'м',
            'n': 'н',
            'o': 'о',
            'p': 'р',
            'q': 'к',
            'r': 'р',
            's': 'с',
            't': 'т',
            'u': 'у',
            'v': 'в',
            'w': 'в',
            'x': 'кс',
            'y': 'и',
            'z': 'з',

            'A': 'А',
            'B': 'Б',
            'C': 'Ц',
            'D': 'Д',
            'E': 'Е',
            'F': 'Ф',
            'G': 'Г',
            'H': 'Х',
            'I': 'И',
            'J': 'Й',
            'K': 'К',
            'L': 'Л',
            'M': 'М',
            'N': 'Н',
            'O': 'О',
            'P': 'Р',
            'Q': 'К',
            'R': 'Р',
            'S': 'С',
            'T': 'Т',
            'U': 'У',
            'V': 'В',
            'W': 'В',
            'X': 'Кс',
            'Y': 'И',
            'Z': 'З',
        }

        # Заменяем латинские символы на кириллические
        for key, value in replacements.items():
            text = text.replace(key, value)

        # Убираем специальные символы и форматирование
        text = re.sub(r'[*_~\\^]', '', text)  # Удаляем символы форматирования
        text = re.sub(r'[\n\r\t]', ' ', text)  # Убираем переносы строк и табуляции
        text = re.sub(r'[^а-яА-ЯёЁ\s]', '', text)  # Оставляем только кириллические буквы и пробелы
        text = re.sub(r'\s+', ' ', text)  # Удаляем лишние пробелы

        return text.lower().strip()

    # Нормализуем входное сообщение
    normalized_text = normalize_text(message_text)

    # Проверка на наличие запрещённых слов в исходном виде
    if any(word in normalized_text for word in FORBIDDEN_WORDS):
        return True

    # Проверка на схожесть с запрещёнными словами
    for forbidden_word in FORBIDDEN_WORDS:
        if fuzz.ratio(normalized_text, forbidden_word) > 80:  # Порог схожести 80%
            return True

    return False


# Обработка заявок на вступление в закрытую группу
@dp.chat_join_request_handler()
async def handle_join_request(join_request: types.ChatJoinRequest):
    chat_id = join_request.chat.id
    user_id = join_request.from_user.id
    user_mention = f"[{join_request.from_user.full_name}](tg://user?id={user_id})"
    
    try:
        # Подтверждаем заявку пользователя
        await bot.approve_chat_join_request(chat_id=chat_id, user_id=user_id)
        logging.info(f"Заявка пользователя {user_mention} на вступление в группу {chat_id} одобрена.")
    except Exception as e:
        logging.error(f"Ошибка при одобрении заявки пользователя {user_id} на вступление: {e}")


# Обработка новых участников
@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_MEMBERS)
async def new_member(message: types.Message):
    chat_id = message.chat.id
    chat_title = message.chat.title if message.chat.title else "Название не указано"

    for new_member in message.new_chat_members:
        user_id = new_member.id
        user_mention = f"[{new_member.full_name}](tg://user?id={user_id})"

        # Логируем действие о новом участнике
        log_group_activity("Новый участник", user=user_mention, chat=chat_title)

        if new_member.id == bot.id:
            await message.reply("Дайте мне права администратора!")
            continue

        # Проверка, есть ли пользователь в базе данных group_members
        if is_user_in_group_db(chat_id, user_id):
            logging.info(f"Пользователь {user_mention} уже находится в базе данных group_members.")
            continue

        keyboard = get_random_keyboard()

        try:
            captcha_message = await bot.send_message(
                chat_id,
                f"Пользователь {user_mention}, 'Висит груша, нельзя скушать'. Выберите правильный ответ:"
                f"\n (У вас 120 сек или будет бан)",
                reply_markup=keyboard,
                parse_mode=types.ParseMode.MARKDOWN
            )

            # Сохраняем данные о капче для данного пользователя
            user_data[user_id] = {'captcha_message_id': captcha_message.message_id, 'chat_id': chat_id}

            # Фоновая задача для бана по истечении времени
            await asyncio.sleep(CAPTCHA_TIMEOUT)
            if user_id in user_data:
                await bot.ban_chat_member(chat_id, user_id)
                await bot.delete_message(chat_id, captcha_message.message_id)
                del user_data[user_id]
                log_group_activity("Пользователь забанен за неответ на капчу", user=user_mention, chat=chat_title)
        except Exception as e:
            logging.error(f"Ошибка при отправке капчи для пользователя {user_id}: {e}")
    try:
        await bot.delete_message(message.chat.id, message.message_id)
        logging.info(f"Сообщение о новом участнике успешно удалено.")
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о новом участнике: {e}")

# Обработка команды /save для добавления пользователя в список "хороших"
@dp.message_handler(commands=['save'])
async def save_user(message: types.Message):
    chat_id = message.chat.id
    user_id = message.from_user.id
    is_admin = (await bot.get_chat_member(chat_id, user_id)).status in ["administrator", "creator"]

    if not is_admin:
        await message.reply("Только администраторы могут добавлять пользователей в список 'хороших'.")
        return

    if message.reply_to_message:
        good_user_id = message.reply_to_message.from_user.id
        if not is_user_in_good_users_db(chat_id, good_user_id):
            add_good_user_to_db(chat_id, good_user_id)
            await message.reply(f"Пользователь {message.reply_to_message.from_user.full_name} добавлен в список 'хороших'.")
            log_group_activity("Пользователь добавлен в список 'хороших'", user=message.reply_to_message.from_user.full_name, chat=message.chat.title)
        else:
            await message.reply(f"Пользователь {message.reply_to_message.from_user.full_name} уже находится в списке 'хороших'.")
    else:
        await message.reply("Эту команду нужно использовать в ответ на сообщение пользователя.")

# Обработка сообщения
@dp.message_handler(content_types=types.ContentTypes.TEXT)
async def handle_text_message(message: types.Message):
    user_id = message.from_user.id
    chat_id = message.chat.id
    user_mention = f"[{message.from_user.full_name}](tg://user?id={user_id})"
    chat_title = message.chat.title or "Название не указано"
    message_text = message.text  # Получаем текст сообщения

    # Проверка, является ли пользователь "хорошим"
    if is_user_in_good_users_db(chat_id, user_id):
        logging.info(f"Сообщение от 'хорошего' пользователя {user_mention} не будет проверяться на запрещенные слова.")
        return  # Пропускаем сообщение от "хороших" пользователей

    # Проверяем наличие запрещенных слов
    if contains_forbidden_words(message_text):
        chat_member = await bot.get_chat_member(chat_id, user_id)

        # Проверяем, что пользователь не является администратором
        if chat_member.status not in ['administrator', 'creator']:
            await bot.ban_chat_member(chat_id, user_id)
            log_group_activity("Пользователь забанен за использование запрещенных слов", user=user_mention, chat=chat_title)
            await bot.delete_message(chat_id, message.message_id)  # Удаляем сообщение с запрещенными словами
        else:
            logging.info(f"Пользователь {user_mention} является администратором и не может быть забанен.")

        return

    # Логируем текст сообщения
    log_group_activity("Пользователь написал сообщение", user=user_mention, chat=chat_title, message=message_text)



# Обработка нажатий на кнопки капчи
@dp.callback_query_handler(lambda c: c.data in emoji_buttons.keys())
async def handle_captcha_answer(callback_query: types.CallbackQuery):
    user_id = callback_query.from_user.id
    chat_id = callback_query.message.chat.id
    selected_answer = callback_query.data

    if user_id in user_data:
        captcha_message_id = user_data[user_id]['captcha_message_id']
        if selected_answer == '💡':  # Правильный ответ: яблоко
            await bot.delete_message(chat_id, captcha_message_id)  # Удаляем сообщение капчи

            await bot.send_message(chat_id, f"Пользователь {callback_query.from_user.full_name} успешно прошел капчу.")
            add_user_to_db(chat_id, user_id)  # Добавляем пользователя в список участников группы
            log_group_activity("Пользователь прошел капчу", user=callback_query.from_user.full_name, chat=callback_query.message.chat.title)
        else:
            await bot.ban_chat_member(chat_id, user_id)  # Баним за неправильный ответ
            await bot.delete_message(chat_id, captcha_message_id)  # Удаляем сообщение капчи
            log_group_activity("Пользователь забанен за неправильный ответ на капчу", user=callback_query.from_user.full_name, chat=callback_query.message.chat.title)

        # Удаляем данные о пользователе после проверки
        del user_data[user_id]
    else:
        await callback_query.answer("Время на решение капчи истекло или вы уже прошли проверку.")

# Запуск бота
if __name__ == '__main__':
    init_group_db()  # Создаем таблицу для участников группы
    init_good_users_db()  # Создаем таблицу для хороших пользователей
    while True:
        try:
            executor.start_polling(dp, skip_updates=False)
        except asyncio.exceptions.TimeoutError:
            logging.warning("Проблемы с сетью. Переподключение через 5 секунд...")
            time.sleep(5)  # Задержка перед повторным запуском
        except Exception as e:
            logging.error(f"Бот упал с ошибкой: {e}. Перезапуск через 5 секунд...")
            time.sleep(5)  # Задержка перед перезапуском
