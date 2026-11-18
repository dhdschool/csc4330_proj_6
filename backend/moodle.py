"""Talks to LSU Moodle (moodle.lsu.edu) using a user's Moodle session cookie.

Nothing here keeps a session of its own: every request takes the session
token it should use, so different users never share one. moodle_sessions.py
decides which token belongs to which user.
"""

import asyncio
import json
import logging
import os
from datetime import date
from typing import Literal

import requests
from bs4 import BeautifulSoup
from playwright.async_api import Error as PlaywrightError
from playwright.async_api import Route, async_playwright

logger = logging.getLogger(__name__)

host: str = "https://moodle.lsu.edu"
SESSION_COOKIE = "MoodleSessionlsumoodle4"

# Moodle can be slow, but a request that never returns ties up a server
# thread and leaves the app stuck on its loading screen.
TIMEOUT_SECONDS = 15


def get_config(html_text: str) -> dict:
  """Reads Moodle's M.cfg object (which holds the sesskey) out of a page."""
  config_line = None

  for line in html_text.splitlines():
    line = line.replace(' ', '')
    if line.find("M.cfg=") >= 0:
      config_line = line

  if config_line is None:
    raise ValueError("Couldn't find M.cfg object in page sent")

  # Find obj terminator
  config_str = config_line.split(";")[0]
  config_str = config_str[len("M.cfg="):]

  return json.loads(config_str)


class BaseRequest:
  endpoint: str
  url: str
  cookies: dict[str, str]
  headers: dict[str, str]
  allow_redirects: bool

  def __init__(self, endpoint: str, headers: dict[str, str] | None = None, cookies: dict[str, str] | None = None, host: str = host, allow_redirects: bool = False, use_post_form: bool = False):
    self.endpoint = endpoint
    self.url = host + endpoint
    self.cookies = {
      "evalkit_101844_105649":"1",
      "acceptCookies": "false",
      "EU_COOKIE_LAW_CONSENT":"false"
    }
    if cookies is not None:
      self.cookies.update(cookies)

    self.headers = {
      "Accept-Encoding": "gzip, deflate, br, zstd",
      "Accept-Language": "en-US,en;q=0.9",
      "Connection": "keep-alive",
      "DNT": "1",
      "Host": "moodle.lsu.edu",
      "Priority": "u=0, i",
      "Sec-GPC": "1",
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:159.0) Gecko/20100101 Firefox/159.0"
    }
    if headers is not None:
      self.headers.update(headers)

    self.allow_redirects = allow_redirects
    self.use_post_form = use_post_form

  def get(self, params: dict[str, str] | None = None) -> requests.Response:
    return requests.get(self.url, params=params, headers=self.headers, cookies=self.cookies, allow_redirects=self.allow_redirects, timeout=TIMEOUT_SECONDS)

  def post(self, params: dict[str, str] | None = None, data: dict | list | None = None) -> requests.Response:
    if not self.use_post_form:
      return requests.post(self.url, params=params, headers=self.headers, cookies=self.cookies, json=data, timeout=TIMEOUT_SECONDS)
    else:
      return requests.post(self.url, params=params, headers=self.headers, cookies=self.cookies, data=data, timeout=TIMEOUT_SECONDS)


def is_authorized(token: str | None) -> bool:
  """Whether a Moodle session token is signed in. Raises requests errors if
  Moodle can't be reached."""
  if not token:
    return False
  resp = BaseRequest("/my/courses.php", cookies={SESSION_COOKIE: token}).get()
  # Signed-out sessions are redirected to the login page instead.
  return resp.status_code == 200


class LoginRequest(BaseRequest):
  def __init__(self):
    super().__init__(endpoint="/login/index.php")

  def start(self) -> tuple[str, str]:
    """Starts a Moodle login.

    Returns the LSU single sign-on URL to open, and the (not yet signed in)
    Moodle session token the login is tied to. Raises requests errors if
    Moodle can't be reached and ValueError if its pages have changed.
    """
    resp = super().get()
    config = get_config(resp.text)
    token = resp.cookies.get(SESSION_COOKIE)
    if not token:
      raise ValueError("Moodle didn't set a session cookie")

    login_request = BaseRequest("/auth/oauth2/login.php", cookies={SESSION_COOKIE: token})
    redir = login_request.get({"id": "1", "wantsurl": "/", "sesskey": config["sesskey"]})
    login_url = redir.headers.get("Location")
    if not login_url:
      raise ValueError("Moodle didn't redirect to the LSU login page")
    return login_url, token

  async def auth_login(self, login_url: str, token: str) -> str:
    """Opens a browser window for the user to finish the LSU login.

    Returns the session token once signed in. Moodle normally issues a new
    one at login; if it doesn't, the original token is returned, and the
    caller should check it with is_authorized().
    """
    new_token: str | None = None

    async with async_playwright() as p:
      browser = await p.chromium.launch(headless=False)
      context = await browser.new_context()
      page = await context.new_page()

      await context.add_cookies([{
        'name': SESSION_COOKIE,
        'value': token,
        'domain': "moodle.lsu.edu",
        'path': '/'
      }])
      done = False

      async def handle_route(route: Route):
        nonlocal done, new_token

        for cookie in await context.cookies():
          if cookie["name"] == SESSION_COOKIE and cookie["value"] != token:
            # Log that it changed, never the cookie itself: it's a credential.
            logger.info("Moodle session changed; login finished")
            new_token = cookie["value"]
            done = True
            await route.abort()
            await browser.close()
            return

        if done:
          await route.abort()
          await browser.close()
          return

        if route.request.url == "https://moodle.lsu.edu/":
          done = True

        await route.continue_()

      try:
        await page.route("**/*", handle_route)
        await page.goto(login_url)
        while not done and not page.is_closed():
          await asyncio.sleep(1)
      except PlaywrightError as error:
        # Closing the browser mid-navigation, or the user closing the window.
        logger.info("Moodle login window closed: %s", error)

    return new_token or token


class AuthRequest(BaseRequest):
  """A request made with a particular user's Moodle session."""

  def __init__(self, endpoint: str, token: str, headers: dict[str, str] | None = None, cookies: dict[str, str] | None = None, use_post_form: bool = False):
    super().__init__(endpoint=endpoint, headers=headers, cookies=cookies, allow_redirects=True, use_post_form=use_post_form)
    self.cookies[SESSION_COOKIE] = token


class ViewCourses(AuthRequest):
  def __init__(self, token: str):
    super().__init__(
      endpoint="/my/courses.php",
      token=token,
      headers={"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-User": "?1", "Upgrade-Insecure-Requests": "1"}
    )

  def post(self):
    raise NotImplementedError("ViewCourses does not have a post request")


class GetCourses(AuthRequest):
  def __init__(self, token: str):
    super().__init__(
      endpoint="/lib/ajax/service.php",
      token=token,
      headers={"Accept": "application/json, text/javascript, */*; q=0.01", "Origin": "https://moodle.lsu.edu", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin", "TE": "trailers", "X-Requested-With": "XMLHttpRequest"}
    )

  def get(self):
    raise NotImplementedError("GetCourses does not have a get request")

  def post(self, sesskey: str) -> requests.Response:
    params={"sesskey": sesskey, "info": "theme_snap_block_myoverview_filters"}
    data=[{"index":0,"methodname":"theme_snap_block_myoverview_filters","args":{"offset":0,"limit":0,"classification":"all","sort":"fullname","customfieldname":"","customfieldvalue":"","yeardata":"All years","progress":"Progress"}}]
    return super().post(params=params, data=data)


class GetScheduleUrl(AuthRequest):
  def __init__(self, token: str):
    super().__init__(
      endpoint="/calendar/export.php",
      token=token,
      use_post_form=True
    )

  def get(self):
    raise NotImplementedError("GetScheduleUrl does not have a get request")

  def post(self, sesskey: str) -> requests.Response:
    return super().post(data={"sesskey": sesskey, "_qf__core_calendar_export_form": "1", "events[exportevents]": "all", "period[timeperiod]": "recentupcoming", "generateurl": "Get calendar URL"})

  def get_calendar_url(self, sesskey: str) -> str:
    resp = self.post(sesskey)
    if resp.status_code != 200:
      raise ValueError(f"Get calendar url returned status code {resp.status_code}")

    url_container = BeautifulSoup(resp.text, "html.parser").find(id="calendarexporturl")
    if url_container is None or not url_container.get("value"):
      raise ValueError("Moodle's export page has no calendar URL")
    return url_container.get("value")


def current_semester(today: date | None = None) -> tuple[Literal['FALL', 'SPRING'], int]:
  """The semester in session: spring for January to May, fall otherwise."""
  today = today or date.today()
  return ('SPRING' if today.month <= 5 else 'FALL'), today.year


class GetCourseSchedule(AuthRequest):
  def __init__(self, token: str):
    super().__init__(endpoint="/blocks/wdsprefs/ical.php", token=token)

  def get(self, semester: Literal['FALL', 'SPRING'] | None = None, year: int | None = None) -> requests.Response:
    default_semester, default_year = current_semester()
    period = f"LSUAM_{semester or default_semester}_{year or default_year}"
    return super().get(params={"periods": period})

  def post(self):
    raise NotImplementedError("Post is not implemented on get course schedule, try get")


if __name__ == "__main__":
  # A manual check against the real Moodle. Signs in through a browser window
  # unless MOODLE_TOKEN holds a signed-in session cookie.
  logging.basicConfig(level=logging.INFO)

  token = os.environ.get("MOODLE_TOKEN", "")
  if not is_authorized(token):
    login = LoginRequest()
    login_url, start_token = login.start()
    token = asyncio.run(login.auth_login(login_url, start_token))

  resp = ViewCourses(token).get()
  logger.info("View courses status code: %s", resp.status_code)

  if resp.status_code == 200:
    sesskey = get_config(resp.text)["sesskey"]

    resp = GetCourses(token).post(sesskey)
    logger.info("Courses status code: %s", resp.status_code)
    if resp.status_code == 200:
      logger.info("Courses: %s", json.dumps(resp.json(), indent=2))

    # The export URL carries a per-user auth token, so don't print it.
    calendar_url = GetScheduleUrl(token).get_calendar_url(sesskey)
    logger.info("Got the calendar export URL")
    logger.info("All Calendar response:\n%s", requests.get(calendar_url, timeout=TIMEOUT_SECONDS).text)
    logger.info("Course schedule response:\n%s", GetCourseSchedule(token).get().text)
