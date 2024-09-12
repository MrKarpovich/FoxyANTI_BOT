import logging
from aiogram import Bot, Dispatcher, types
from aiogram.types import InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.utils import executor
from datetime import datetime
import asyncio

API_TOKEN = 'ключ'

logging.basicConfig(level=logging.INFO)

bot = Bot(token=API_TOKEN)
dp = Dispatcher(bot)

CAPTCHA_TIMEOUT = 120  # Время на решение капчи в секундах

user_data = {}  # Хранит данные о пользователях и время их капчи

# Кнопки для выбора
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

@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_MEMBERS)
async def new_member(message: types.Message):
    chat_id = message.chat.id
    for new_member in message.new_chat_members:
        user_id = new_member.id
        user_mention = f"[{new_member.full_name}](tg://user?id={user_id})"

        keyboard = InlineKeyboardMarkup(row_width=3)
        buttons = [InlineKeyboardButton(text=emoji, callback_data=emoji) for emoji in emoji_buttons.keys()]
        keyboard.add(*buttons)

        user_data[user_id] = {'captcha': True, 'time': datetime.now(), 'chat_id': chat_id, 'message_id': None}

        # Отправляем сообщение с капчей в группу
        try:
            captcha_message = await bot.send_message(
                chat_id,
                f"Пользователь {user_mention}, выбери самое полезное из перечисленного: (У вас 120 сек или будет бан)",
                reply_markup=keyboard,
                parse_mode=types.ParseMode.MARKDOWN
            )
            user_data[user_id]['message_id'] = captcha_message.message_id
        except Exception as e:
            logging.error(f"Ошибка при отправке сообщения с капчей для пользователя {user_id}: {e}")

@dp.callback_query_handler(lambda c: c.data in emoji_buttons.keys())
async def process_captcha(callback_query: types.CallbackQuery):
    user_id = callback_query.from_user.id

    if user_id in user_data:
        captcha_data = user_data[user_id]
        if captcha_data.get('captcha'):
            if (datetime.now() - captcha_data['time']).total_seconds() <= CAPTCHA_TIMEOUT:
                if callback_query.data == '🍎':  # Проверяем, выбрано ли яблоко
                    await bot.answer_callback_query(callback_query.id, text="Вы успешно прошли капчу!")
                    chat_id = captcha_data['chat_id']
                    await bot.delete_message(chat_id, captcha_data['message_id'])  # Удаляем сообщение с капчей

                    # Отправляем приветственное сообщение
                    welcome_message = await bot.send_message(chat_id, f"Привет, {callback_query.from_user.full_name}! Добро пожаловать в группу!")
                    await asyncio.sleep(30)  # Ждем 30 секунд
                    await bot.delete_message(chat_id, welcome_message.message_id)  # Удаляем приветственное сообщение

                    # Удаляем данные о пользователе после прохождения капчи
                    del user_data[user_id]
                else:
                    await bot.answer_callback_query(callback_query.id, text="Неверный ответ. Вы были забанены.")
                    chat_id = captcha_data['chat_id']
                    try:
                        await bot.ban_chat_member(chat_id, user_id)
                    except Exception as e:
                        logging.error(f"Ошибка при бане пользователя {user_id}: {e}")

                    await bot.delete_message(chat_id, captcha_data['message_id'])
                    del user_data[user_id]  # Удаляем данные о пользователе
            else:
                await bot.answer_callback_query(callback_query.id, text="Время на ответ истекло.")
                chat_id = captcha_data['chat_id']
                try:
                    await bot.ban_chat_member(chat_id, user_id)
                except Exception as e:
                    logging.error(f"Ошибка при бане пользователя {user_id}: {e}")
                await bot.delete_message(chat_id, captcha_data['message_id'])
                del user_data[user_id]
        else:
            await bot.answer_callback_query(callback_query.id, text="Вы не видели капчу.")
    else:
        await bot.answer_callback_query(callback_query.id, text="Вы не можете проходить эту капчу.")

@dp.message_handler(content_types=types.ContentTypes.LEFT_CHAT_MEMBER)
async def member_left(message: types.Message):
    # Удаляем сообщение о том, кто покинул группу
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о выходе: {e}")

@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_PHOTO)
async def chat_photo_changed(message: types.Message):
    # Удаляем сообщение о смене фото группы
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о смене фото: {e}")

@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_TITLE)
async def chat_title_changed(message: types.Message):
    # Удаляем сообщение о смене названия группы
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о смене названия: {e}")

@dp.message_handler(content_types=types.ContentTypes.NEW_CHAT_MEMBERS)
async def handle_invite_link(message: types.Message):
    # Удаляем сообщения о том, кто присоединился по приглашению
    try:
        await bot.delete_message(message.chat.id, message.message_id)
    except Exception as e:
        logging.error(f"Ошибка при удалении сообщения о присоединении: {e}")

async def check_timeouts():
    while True:
        current_time = datetime.now()
        for user_id, data in list(user_data.items()):
            if data['captcha'] and (current_time - data['time']).total_seconds() > CAPTCHA_TIMEOUT:
                chat_id = data.get('chat_id')
                if chat_id:
                    try:
                        await bot.ban_chat_member(chat_id, user_id)
                    except Exception as e:
                        logging.error(f"Ошибка при бане пользователя {user_id}: {e}")
                if 'message_id' in data:
                    await bot.delete_message(chat_id, data['message_id'])
                del user_data[user_id]
        await asyncio.sleep(60)

if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    loop.create_task(check_timeouts())
    executor.start_polling(dp, skip_updates=True)
