import json
import os
import uuid
from datetime import datetime, timedelta

from safe_io import atomic_write_json

DATA_DIR = os.getenv("PROJECTTRACKER_DATA_DIR", os.getcwd())
os.makedirs(DATA_DIR, exist_ok=True)
ANKI_FILE = os.path.join(DATA_DIR, "anki.json")


def load_anki_data():
    """Loads flashcard data from JSON file."""
    if not os.path.exists(ANKI_FILE):
        return {"cards": []}
    try:
        with open(ANKI_FILE, 'r', encoding='utf-8') as file:
            return json.load(file)
    except json.JSONDecodeError:
        print(f"Error decoding JSON from {ANKI_FILE}. Returning empty card list.")
        return {"cards": []}


def save_anki_data(data):
    """Saves flashcard data to JSON file atomically."""
    atomic_write_json(ANKI_FILE, data)


def create_card(front, back, reverse=False):
    """Creates a new flashcard and its reverse if specified."""
    data = load_anki_data()
    today = datetime.now().strftime("%Y-%m-%d")

    # Create main card
    card_id = uuid.uuid4().hex
    new_card = {
        "id": card_id,
        "front": front,
        "back": back,
        "reverse": reverse,
        "easiness_factor": 2.5,
        "interval": 1,
        "repetitions": 0,
        "review_date": today,
        "created_date": today
    }
    if "cards" not in data:
        data["cards"] = []
    data["cards"].append(new_card)

    # Create reverse card if requested
    if reverse:
        reverse_id = uuid.uuid4().hex
        reverse_card = {
            "id": reverse_id,
            "front": back,
            "back": front,
            "reverse": False,  # Don't mark the reverse card as reverse
            "easiness_factor": 2.5,
            "interval": 1,
            "repetitions": 0,
            "review_date": today,
            "created_date": today
        }
        data["cards"].append(reverse_card)

    save_anki_data(data)
    return card_id


def get_card(card_id):
    """Retrieves a specific flashcard by ID."""
    data = load_anki_data()
    return next((card for card in data.get("cards", []) if card["id"] == card_id), None)


def update_card(card_id, front, back, reverse=False):
    """Updates an existing flashcard."""
    data = load_anki_data()
    cards = data.get("cards", [])
    card = next((c for c in cards if c["id"] == card_id), None)

    if card:
        original_back = card["back"]
        was_reverse = card.get("reverse", False)

        # Update the main card
        card["front"] = front
        card["back"] = back
        card["reverse"] = reverse

        # Find the potential reverse card based on the *original* content
        reverse_card = next((
            c for c in cards
            if c.get("front") == original_back and c.get("back") == card["front"]
        ), None)

        # Case 1: Turning on reverse for the first time
        if reverse and not was_reverse:
            # Check if a reverse card doesn't already exist accidentally
            if not reverse_card:
                create_card(back, front, reverse=False) # Create a new one
        # Case 2: Turning off reverse
        elif not reverse and was_reverse:
            if reverse_card:
                data["cards"] = [c for c in cards if c["id"] != reverse_card["id"]]
        # Case 3: Reverse was on and is still on (content changed)
        elif reverse and was_reverse:
            if reverse_card:
                reverse_card["front"] = back
                reverse_card["back"] = front

        save_anki_data(data)


def delete_card(card_id):
    """Deletes a flashcard and its reverse if it exists."""
    data = load_anki_data()
    cards = data.get("cards", [])
    card_to_delete = next((c for c in cards if c["id"] == card_id), None)

    if not card_to_delete:
        return

    # First, identify all card IDs to be removed
    ids_to_remove = {card_id}
    if card_to_delete.get("reverse"):
        # Find the corresponding reverse card to delete as well
        reverse_card = next((
            c for c in cards
            if c.get("front") == card_to_delete["back"] and c.get("back") == card_to_delete["front"]
        ), None)
        if reverse_card:
            ids_to_remove.add(reverse_card["id"])

    # Filter the card list in one go
    data["cards"] = [c for c in cards if c["id"] not in ids_to_remove]
    save_anki_data(data)


def get_due_cards():
    """Returns all cards due for review."""
    data = load_anki_data()
    today = datetime.now().strftime("%Y-%m-%d")

    due_cards = [card for card in data.get("cards", [])
                 if card.get("review_date", "9999-12-31") <= today]

    return due_cards


def process_card_review(card_id, rating):
    """Processes a card review using the SM2 algorithm."""
    data = load_anki_data()
    card = next((card for card in data.get("cards", []) if card["id"] == card_id), None)

    if card:
        rating = int(rating)
        # Apply SM2 algorithm
        if rating < 3:
            card["repetitions"] = 0
            card["interval"] = 1
        else:
            if card.get("repetitions", 0) == 0:
                card["interval"] = 1
            elif card["repetitions"] == 1:
                card["interval"] = 6
            else:
                card["interval"] = round(card.get("interval", 1) * card.get("easiness_factor", 2.5))
            card["repetitions"] = card.get("repetitions", 0) + 1

        # Update easiness factor
        easiness = card.get("easiness_factor", 2.5)
        new_easiness = easiness + (0.1 - (5 - rating) * (0.08 + (5 - rating) * 0.02))
        card["easiness_factor"] = max(1.3, new_easiness)

        # Calculate next review date
        next_date = datetime.now() + timedelta(days=card.get("interval", 1))
        card["review_date"] = next_date.strftime("%Y-%m-%d")

        save_anki_data(data)
