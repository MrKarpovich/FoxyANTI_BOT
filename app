import logging
import random
from aiogram import Bot, Dispatcher, types
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.utils import executor
from datetime import datetime
import asyncio
import time

API_TOKEN = '-'

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
dp = Dispatcher(bot)

CAPTCHA_TIMEOUT = 120  # Время на решение капчи (в секундах)
user_data = {}  # Хранит данные пользователей, статус капчи и ID сообщений
user_passed = {}  # Отслеживает пользователей, прошедших капчу

emoji_buttons = {
    '🍎': 'Яблоко',
    '🍕': 'Пицца',
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
}

# Функция для перемешивания кнопок
def get_random_keyboard():
    keyboard = InlineKeyboardMarkup(row_width=3)
    buttons = [InlineKeyboardButton(text=emoji, callback_data=emoji) for emoji in emoji_buttons.keys()]
    random.shuffle(buttons)  # Перемешиваем список кнопок
    keyboard.add(*buttons)
    return keyboard

# Функция для отправки капчи новому участнику
@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_MEMBERS)
async def new_member(message: types.Message):
    chat_id = message.chat.id
    for new_member in message.new_chat_members:
        if new_member.id == bot.id:
            await message.reply("Дайте мне права администратора!")
            continue

        user_id = new_member.id
        user_mention = f"[{new_member.full_name}](tg://user?id={user_id})"

        keyboard = get_random_keyboard()  # Генерируем перемешанные кнопки

        # Если пользователь повторно заходит, удаляем старую капчу
        if user_id in user_data:
            await bot.delete_message(chat_id, user_data[user_id]['message_id'])
            del user_data[user_id]

        # Если пользователь уже проходил капчу, убираем его из user_passed
        if user_id in user_passed:
            del user_passed[user_id]

        # Сохраняем данные о пользователе и отправляем капчу
        user_data[user_id] = {'captcha': True, 'time': datetime.now(), 'chat_id': chat_id, 'message_id': None}
        try:
            captcha_message = await bot.send_message(
                chat_id,
                f"Пользователь {user_mention}, выбери самое полезное из перечисленного: \n(У вас 120 сек или будет бан)",
                reply_markup=keyboard,
                parse_mode=types.ParseMode.MARKDOWN
            )
            user_data[user_id]['message_id'] = captcha_message.message_id
        except Exception as e:
            logging.error(f"Ошибка при отправке сообщения с капчей для пользователя {user_id}: {e}")

# Обработка ответа на капчу
@dp.callback_query_handler(lambda c: c.data in emoji_buttons.keys())
async def process_captcha(callback_query: types.CallbackQuery):
    user_id = callback_query.from_user.id

    if user_id in user_data:
        captcha_data = user_data[user_id]
        if captcha_data.get('captcha'):
            if (datetime.now() - captcha_data['time']).total_seconds() <= CAPTCHA_TIMEOUT:
                if callback_query.message.message_id == captcha_data['message_id']:
                    if callback_query.data == '🍎':  # Правильный ответ (Яблоко)
                        await bot.answer_callback_query(callback_query.id, text="Вы успешно прошли капчу!")
                        chat_id = captcha_data['chat_id']
                        try:
                            await bot.delete_message(chat_id, captcha_data['message_id'])  # Удаляем сообщение с капчей
                        except Exception as e:
                            logging.warning(f"Ошибка при удалении сообщения с капчей: {e}")

                        welcome_message = await bot.send_message(chat_id, f"Привет, {callback_query.from_user.full_name}! Добро пожаловать в группу!")
                        await asyncio.sleep(30)  # Ожидаем 30 секунд
                        await bot.delete_message(chat_id, welcome_message.message_id)  # Удаляем приветственное сообщение

                        # Отмечаем пользователя как прошедшего капчу
                        user_passed[user_id] = True
                        del user_data[user_id]
                    else:
                        await bot.answer_callback_query(callback_query.id, text="Неверный ответ. Вы были забанены.")
                        await ban_user(callback_query.message.chat.id, user_id)
                else:
                    await bot.answer_callback_query(callback_query.id, text="Вы не можете проходить эту капчу.")
            else:
                await bot.answer_callback_query(callback_query.id, text="Время на ответ истекло.")
                await ban_user(callback_query.message.chat.id, user_id)
        else:
            await bot.answer_callback_query(callback_query.id, text="Вы не видели капчу.")
    else:
        await bot.answer_callback_query(callback_query.id, text="Вы не можете проходить эту капчу.")

# Бан пользователя и удаление сообщений
async def ban_user(chat_id, user_id):
    try:
        await bot.ban_chat_member(chat_id, user_id)
        if user_id in user_data:
            try:
                await bot.delete_message(chat_id, user_data[user_id]['message_id'])
            except Exception as e:
                logging.warning(f"Ошибка при удалении сообщения с капчей: {e}")
            del user_data[user_id]
    except Exception as e:
        logging.error(f"Ошибка при бане пользователя {user_id}: {e}")

# Удаление сообщений от пользователей, не прошедших капчу
@dp.message_handler()
async def delete_messages_from_unverified_users(message: types.Message):
    user_id = message.from_user.id

    if user_id in user_data and user_id not in user_passed:
        try:
            await bot.delete_message(message.chat.id, message.message_id)
        except Exception as e:
            logging.error(f"Ошибка при удалении сообщения от пользователя {user_id}: {e}")
    else:
        pass

# Удаление сообщений о выходе из группы
@dp.message_handler(content_types=types.ContentTypes.LEFT_CHAT_MEMBER)
async def member_left(message: types.Message):
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о выходе: {e}")

# Удаление обновлений фото группы
@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_PHOTO)
async def chat_photo_changed(message: types.Message):
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о смене фото: {e}")

# Удаление обновлений названия группы
@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_TITLE)
async def chat_title_changed(message: types.Message):
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о смене названия: {e}")

# Фоновая задача для проверки таймаутов капчи
async def check_timeouts():
    while True:
        current_time = datetime.now()
        for user_id, data in list(user_data.items()):
            if data['captcha'] and (current_time - data['time']).total_seconds() > CAPTCHA_TIMEOUT:
                await ban_user(data.get('chat_id'), user_id)
        await asyncio.sleep(60)

if __name__ == '__main__':
    try:
        loop = asyncio.get_event_loop()
        loop.create_task(check_timeouts())
        executor.start_polling(dp, skip_updates=True)
    except Exception as e:
        logging.error(f"Ошибка при запуске бота: {e}")
        time.sleep(5)
