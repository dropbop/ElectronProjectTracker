from flask import Flask, render_template, request, redirect, url_for, abort
import os
import sys
from operator import itemgetter
from datetime import datetime, timedelta

# --- enable absolute imports even if someone runs `python src/app.py` ---
if __package__ is None and __name__ == "__main__":
    # add repo root (parent of /src) to sys.path so `import src.*` works
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# ---- absolute imports so PyInstaller won't choke ----
from src.data_handler import (
    get_project, get_projects_by_category, create_project, update_project,
    create_task, update_task, get_all_tasks, add_project_update, delete_project_update,
    load_data
)
import src.utils as utils

# --- Anki Imports (optional module) ---
try:
    from src.anki import (
        load_anki_data, save_anki_data, create_card, get_card, update_card,
        delete_card, get_due_cards, process_card_review
    )
    anki_enabled = True
except ImportError:
    print("WARNING: Anki module not found. Anki features will be disabled.")
    anki_enabled = False
    def load_anki_data(): return {"cards": []}
    def save_anki_data(data): pass
    def create_card(f, b, r): pass
    def get_card(id): return None
    def update_card(id, f, b, r): pass
    def delete_card(id): pass
    def get_due_cards(): return []
    def process_card_review(id, r): pass
# --- End Anki Imports ---

# In a PyInstaller EXE, assets are unpacked to sys._MEIPASS.
# In dev, our templates/static live in the PROJECT ROOT (parent of /src).
if hasattr(sys, "_MEIPASS"):
    base_dir = sys._MEIPASS
else:
    base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

app = Flask(
    __name__,
    template_folder=os.path.join(base_dir, "templates"),
    static_folder=os.path.join(base_dir, "static"),
)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "your_default_secret_key")
STATIC_FOLDER = app.static_folder


@app.context_processor
def inject_css_and_static_folder():
    """Inject CSS file list and STATIC_FOLDER into templates."""
    return {**utils.inject_css_files(STATIC_FOLDER), 'STATIC_FOLDER': STATIC_FOLDER}


@app.route("/__health")
def health():
    return "ok"


@app.route('/set_style', methods=['POST'])
def set_style_route():
    utils.set_style(request, STATIC_FOLDER)
    return redirect(request.referrer)

# --- Project Management Routes ---

@app.route("/add_project", methods=["GET", "POST"])
def add_project():
    if request.method == "POST":
        title = request.form["title"]
        description = request.form.get("description", "")
        start_date = request.form["start_date"]
        target_completion_date = request.form.get("target_completion_date")
        status = request.form.get("status", "active")
        create_project(title, description, start_date, target_completion_date, status)
        return redirect(url_for("list_projects_by_category", category=status))
    return render_template("add_project.html")


@app.route("/project/<project_id>")
def view_project(project_id):
    project = get_project(project_id, task_status='active')
    if not project:
        abort(404)

    sort_by = request.args.get('sort_by', 'due_date')
    order = request.args.get('order', 'asc')
    selected_task_statuses = request.args.getlist('task_status')

    if sort_by == 'due_date':
        project['tasks'].sort(
            key=lambda x: x.get('target_completion_date', '') or '9999-12-31',
            reverse=(order == 'desc')
        )

    if selected_task_statuses:
        all_project_tasks = get_project(project_id)['tasks']
        project['tasks'] = [t for t in all_project_tasks if t['status'] in selected_task_statuses]
        if sort_by == 'due_date':
            project['tasks'].sort(
                key=lambda x: x.get('target_completion_date', '') or '9999-12-31',
                reverse=(order == 'desc')
            )
    else:
        selected_task_statuses = ['active']

    return render_template(
        "project_detail.html",
        project_id=project_id,
        project=project,
        sort_by=sort_by,
        order=order,
        selected_task_statuses=selected_task_statuses
    )


@app.route("/add_task/<project_id>", methods=["POST"])
def add_task(project_id):
    project = get_project(project_id)
    if not project:
        abort(404)

    description = request.form["description"]
    additional_info = request.form.get("additional_info", "")
    start_date = request.form.get("start_date")
    target_completion_date = request.form.get("target_completion_date")
    actual_completion_date = request.form.get("actual_completion_date")
    status = request.form["status"]

    create_task(project_id, description, additional_info, start_date,
                target_completion_date, actual_completion_date, status)
    return redirect(url_for("view_project", project_id=project_id))


@app.route("/", defaults={"category": "active"})
@app.route("/projects", defaults={"category": "active"})
@app.route("/projects/<category>")
def list_projects_by_category(category):
    valid_categories = ["active", "on hold", "complete", "archived", "ongoing"]
    if category not in valid_categories:
        return redirect(url_for("list_projects_by_category", category="active"))

    projects = get_projects_by_category(category)

    sort_by = request.args.get('sort_by', 'next_task_due_date')
    sort_order = request.args.get('order', 'asc')

    if sort_by == 'start_date':
        projects.sort(key=itemgetter('start_date'), reverse=(sort_order == 'desc'))
    elif sort_by == 'target_completion_date':
        projects.sort(key=lambda p: p.get('target_completion_date') or '9999-12-31',
                      reverse=(sort_order == 'desc'))
    elif sort_by == 'next_task_due_date':
        projects.sort(key=lambda p: p.get('next_task_due_date', '9999-12-31'),
                      reverse=(sort_order == 'desc'))

    return render_template(
        "projects.html",
        projects=projects,
        current_category=category,
        categories=valid_categories,
        sort_by=sort_by,
        sort_order=sort_order
    )


@app.route('/project/<project_id>/edit', methods=['GET', 'POST'])
def edit_project(project_id):
    project = get_project(project_id)
    if not project:
        abort(404)

    sort_by = request.args.get('sort_by', 'start_date')
    order = request.args.get('order', 'asc')

    if request.method == "POST":
        title = request.form["title"]
        description = request.form.get("description", "")
        status = request.form["status"]
        start_date = request.form["start_date"]
        target_completion_date = request.form.get("target_completion_date")
        actual_completion_date = request.form.get("actual_completion_date")

        update_ids = request.form.getlist("update_ids[]")
        update_texts = request.form.getlist("update_texts[]")
        existing_updates_map = {u['id']: u['timestamp'] for u in project.get('updates', [])}
        new_updates = [{
            'id': uid,
            'timestamp': existing_updates_map.get(uid, datetime.now().isoformat()),
            'description': utxt
        } for uid, utxt in zip(update_ids, update_texts)]

        update_project(project_id, title, description, status, start_date,
                       target_completion_date, actual_completion_date, new_updates)
        return redirect(url_for("view_project", project_id=project_id))

    tasks = project.get('tasks', [])
    if sort_by == 'start_date':
        tasks.sort(key=lambda x: x.get('start_date', '') or '9999-12-31', reverse=(order == 'desc'))
    elif sort_by == 'status':
        status_order = {'active': 0, 'on hold': 1, 'complete': 2, 'archived': 3, 'ongoing': 4}
        tasks.sort(key=lambda x: status_order.get(x.get('status'), 999), reverse=(order == 'desc'))
    project['tasks'] = tasks

    return render_template('edit_project.html', project=project, sort_by=sort_by, order=order,
                           show_delete_buttons=True)


@app.route("/edit_task/<project_id>/<task_id>", methods=["GET", "POST"])
def edit_task(project_id, task_id):
    project = get_project(project_id)
    if not project:
        abort(404)

    task = next((t for t in project.get('tasks', []) if t['id'] == task_id), None)
    if not task:
        abort(404)

    if request.method == "POST":
        description = request.form["description"]
        additional_info = request.form.get("additional_info", "")
        status = request.form["status"]
        start_date = request.form.get("start_date")
        target_completion_date = request.form.get("target_completion_date")
        actual_completion_date = request.form.get("actual_completion_date")
        update_task(project_id, task_id, description, additional_info, status,
                    start_date, target_completion_date, actual_completion_date)
        return redirect(url_for("view_project", project_id=project_id))

    return render_template("edit_task.html", project_id=project_id, task=task)


@app.route('/tasks')
def list_all_tasks():
    sort_by = request.args.get('sort_by', 'due_date')
    order = request.args.get('order', 'asc')
    selected_project_statuses = request.args.getlist('project_status') or ['active', 'ongoing']
    selected_task_statuses = request.args.getlist('task_status') or ['active']

    tasks = get_all_tasks(sort_by, order, selected_project_statuses, selected_task_statuses)
    return render_template('tasks.html', tasks=tasks, sort_by=sort_by, order=order,
                           selected_project_statuses=selected_project_statuses,
                           selected_task_statuses=selected_task_statuses)


@app.route("/project/<project_id>/add_update", methods=["POST"])
def add_update(project_id):
    project = get_project(project_id)
    if not project:
        abort(404)
    update_text = request.form.get("update_text")
    if update_text:
        add_project_update(project_id, update_text)
    return redirect(url_for("edit_project", project_id=project_id))


@app.route("/project/<project_id>/delete_update/<update_id>", methods=["POST"])
def delete_update(project_id, update_id):
    project = get_project(project_id)
    if not project:
        abort(404)
    delete_project_update(project_id, update_id)
    return redirect(url_for("edit_project", project_id=project_id))


@app.route("/calendar")
def productivity_calendar():
    try:
        data = load_data()
        completion_dates = []
        for project in data.get('projects', []):
            if project.get('actual_completion_date'):
                completion_dates.append(project['actual_completion_date'])
            for task in project.get('tasks', []):
                if task.get('actual_completion_date'):
                    completion_dates.append(task['actual_completion_date'])

        date_counts = {}
        for date_str in completion_dates:
            try:
                date = datetime.strptime(date_str, '%Y-%m-%d').date()
                date_counts[date] = date_counts.get(date, 0) + 1
            except (ValueError, TypeError):
                continue

        today = datetime.today().date()
        total_days = 53 * 7
        start_date = today - timedelta(days=total_days - 1)
        calendar_dates = [start_date + timedelta(days=i) for i in range(total_days)]
        if not calendar_dates:
            calendar_dates = [today]
    except Exception as e:
        print(f"Error generating calendar data: {e}")
        date_counts = {}
        today = datetime.today().date()
        total_days = 53 * 7
        start_date = today - timedelta(days=total_days - 1)
        calendar_dates = [start_date + timedelta(days=i) for i in range(total_days)]

    return render_template("calendar.html", date_counts=date_counts,
                           calendar_dates=calendar_dates, today=today)


# --- Anki Routes ---
if anki_enabled:
    @app.route("/anki")
    def anki_review():
        try:
            due_cards = get_due_cards()
            return render_template("anki.html", due_cards=due_cards)
        except Exception as e:
            print(f"Error getting due Anki cards: {e}")
            return render_template("anki.html", due_cards=[], error="Could not load due cards.")

    @app.route("/anki/review/<card_id>", methods=["POST"])
    def review_card(card_id):
        try:
            rating = int(request.form["rating"])
            process_card_review(card_id, rating)
            return redirect(url_for("anki_review"))
        except Exception as e:
            print(f"Error processing Anki card review: {e}")
            return redirect(url_for("anki_review"))

    @app.route("/anki/manage")
    def manage_cards():
        try:
            data = load_anki_data()
            return render_template("edit_anki.html", cards=data.get("cards", []), mode='list')
        except Exception as e:
            print(f"Error loading Anki data: {e}")
            return render_template("edit_anki.html", cards=[], mode='list', error="Could not load card data.")

    @app.route("/anki/add", methods=["GET", "POST"])
    def add_card():
        if request.method == "POST":
            try:
                front = request.form["front"]
                back = request.form["back"]
                reverse = "reverse" in request.form
                create_card(front, back, reverse)
                return redirect(url_for("manage_cards"))
            except Exception as e:
                print(f"Error adding Anki card: {e}")
                return render_template("edit_anki.html", mode='add', error="Failed to add card.")
        return render_template("edit_anki.html", mode='add')

    @app.route("/anki/edit/<card_id>", methods=["GET", "POST"])
    def edit_card(card_id):
        try:
            card = get_card(card_id)
            if not card:
                abort(404)
            if request.method == "POST":
                front = request.form["front"]
                back = request.form["back"]
                reverse = "reverse" in request.form
                update_card(card_id, front, back, reverse)
                return redirect(url_for("manage_cards"))
            return render_template("edit_anki.html", card=card, mode='edit')
        except Exception as e:
            print(f"Error editing card {card_id}: {e}")
            return redirect(url_for("manage_cards"))

    @app.route("/anki/delete/<card_id>", methods=["POST"])
    def delete_card_route(card_id):
        try:
            delete_card(card_id)
            return redirect(url_for("manage_cards"))
        except Exception as e:
            print(f"Error deleting card {card_id}: {e}")
            return redirect(url_for("manage_cards"))
else:
    @app.route("/anki")
    @app.route("/anki/manage")
    @app.route("/anki/add")
    @app.route("/anki/edit/<card_id>")
    def anki_disabled(*_args, **_kwargs):
        return "Anki functionality is currently disabled because the 'anki' module could not be found.", 404


if __name__ == "__main__":
    port = int(os.environ.get("PROJECTTRACKER_PORT", 0))
    app.run(host="127.0.0.1", port=port, debug=False)
