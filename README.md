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

If running flutter web, the backend additionally needs to login to moodle as there are no flutter webview for flutter web. To do this, run this from the backend folder

```
playwright install
```

When running the frontend on mobile, the frontend should be able to render the webview for IOS and Android without needing to login on the backend. 

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

### `GET /api/tigerlink/events`

Returns club and organization events from the public [TigerLink](https://tigerlink.lsu.edu/events) (CampusGroups) iCal feed, cached in memory for 1 hour.

| Query parameter | Description |
| --- | --- |
| `start`, `end` | Dates as `YYYY-MM-DD`. Returns events overlapping this window. |
| `club` | A club acronym or name, case-insensitive. |
| `event_type` | For example `Service` or `Meeting`. |
| `search` | Matches the event title, case-insensitive. |
| `limit` | Most events to return (default 500). Events are sorted by start time, so pass `start` to get upcoming ones rather than the earliest. |

Each event has `start`/`end` as UTC timestamps, plus `club`, `event_type`, `tags`, `location` and `url`. A `location` of `null` means TigerLink only shows it to signed-in users. `stale` is `true` if the last refresh failed.

For the map, each event also has:

- `venue`: the location without the default "Campus Life, 358J LSU Student Union" address TigerLink appends to most campus locations, e.g. `167 Coates Hall`. Use this for display.
- `place`, `latitude`, `longitude`: the campus building the venue matched, from the table in `campus_places.py`. They're `null` for off-campus addresses, online or TBD events, and buildings the table doesn't cover (such as White Hall, which isn't in OpenStreetMap).

## Frontend

A Flutter app with three tabs: a month view of the LSU academic calendar, an agenda with a banner counting down to the next break, and a Clubs tab for TigerLink events. The Clubs tab shows events from clubs you follow by default, with an "All" view, search and type filters. Followed clubs are saved on the device with `shared_preferences`; there's no account, since TigerLink memberships aren't available without LSU's authorized API. Start the backend first, then from the `frontend` folder:

```
flutter pub get
flutter run -d chrome
flutter test
```

The app calls `http://localhost:8000`, or `http://10.0.2.2:8000` on the Android emulator. To use a different backend, pass `--dart-define=BACKEND_URL=https://your-server`.

If the emulator can't reach `10.0.2.2:8000` (a VPN on the host can block it), tunnel the port over adb instead and point the app at localhost:

```
adb reverse tcp:8000 tcp:8000
flutter run --dart-define=BACKEND_URL=http://localhost:8000
```
