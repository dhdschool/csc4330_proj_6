# CSC4330 App 6

Calendar app synchronizing

## Backend

Requires Python 3.12 or newer. From the `backend` folder:

```
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt -r requirements-dev.txt
uvicorn main:app --reload
pytest
```

On macOS or Linux, activate with `source .venv/bin/activate`. While the server is running, interactive API docs are at http://localhost:8000/docs.

### `GET /api/lsu/calendar/events`

Returns the LSU academic calendar, scraped from the [Registrar's pages](https://www.lsu.edu/registrar/academics/academic-calendars/index.php) and cached in memory for 24 hours.

| Query parameter | Description |
| --- | --- |
| `start`, `end` | Dates as `YYYY-MM-DD`. Returns events overlapping this window. |
| `category` | `holiday`, `classes`, `exam`, `deadline`, `grades`, `registration`, `study_period`, `orientation`, `commencement` or `other`. Repeat to allow several. |
| `term` | A term name, such as `Spring Semester 2027`. |

The response contains:

- `events`: dated events, sorted by start date.
- `unscheduled`: events LSU hasn't dated yet, such as `TBD` entries. Their dates are null.
- `stale`: `true` if the last refresh from LSU failed, so data may be old or incomplete.

For holidays that cover part of a day, `classes_end_at` and `classes_resume_at` give the time classes stop or restart. Summer Break only applies to long session classes, as its `description` says.

## Frontend

A Flutter app that shows the LSU academic calendar: a month view, an agenda of upcoming dates, and a holidays tab that counts down to the next break. Start the backend first, then from the `frontend` folder:

```
flutter pub get
flutter run -d chrome
flutter test
```

The app calls `http://localhost:8000`, or `http://10.0.2.2:8000` on the Android emulator. To use a different backend, pass `--dart-define=BACKEND_URL=https://your-server`.
