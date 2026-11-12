import requests
import json
import os
import asyncio
from playwright.async_api import async_playwright, Route
from bs4 import BeautifulSoup
from typing import Literal
import logging

ENV_FP = "moodle.env"

def read_env():
  try:
    with open(ENV_FP, "r") as file:
      envs = file.readlines()
      envs_idx = [env.find("=") for env in envs]
      if -1 in envs_idx or 0 in envs_idx:
        raise ValueError("Invalid .env format")
      
      envs = {env[:idx]:env[idx+1:].strip() for idx, env in zip(envs_idx, envs)}
      os.environ.update(envs)
  except FileNotFoundError as e:
    return
  
read_env()
host: str = "https://moodle.lsu.edu"

moodle4_token: str = os.environ.get("moodle4_token_default", "")

def get_config(html_text: str) -> dict:
  lines = html_text.splitlines()
  config_line = None
  
  for line in lines:
    line = line.replace(' ', '')
    if line.find("M.cfg=") >= 0:
      config_line = line
      
  if config_line == None:
    # Can't find session key
    raise ValueError("Couldn't find M.cfg object in page sent")
  
  # Find obj terminator
  config_str = config_line.split(";")[0]
  config_str = config_str[len("M.cfg="):]
  
  config = json.loads(config_str)
  
  return config

class BaseRequest:
  endpoint: str
  url: str
  cookies: dict[str, str] 
  headers: dict[str, str]
  allow_redirects: bool
  
  def __init__(self, endpoint: str, headers: dict[str, str] = {}, cookies: dict[str, str] = {}, host: str = host, allow_redirects: bool = False, use_post_form: bool = False):
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
    return requests.get(self.url, params=params, headers=self.headers, cookies=self.cookies, allow_redirects=self.allow_redirects)

  def post(self, params: dict[str, str] | None = None, data: dict | list | None = None) -> requests.Response:
    
    if not self.use_post_form:
      return requests.post(self.url, params=params, headers=self.headers, cookies=self.cookies, json=data)
    else:
      return requests.post(self.url, params=params, headers=self.headers, cookies=self.cookies, data=data)
    
    
class LoginRequest(BaseRequest):
  def __init__(self):
    super().__init__(endpoint="/login/index.php")
  
  def get(self) -> requests.Response:
    global moodle4_token      
    
    resp = super().get()
    config = get_config(resp.text)
    logging.log(level=logging.INFO, msg=f"Cookies: {resp.cookies}")
    logging.log(level=logging.INFO, msg=f"Login sesskey: {config["sesskey"]}")
    
    moodle4_token = resp.cookies['MoodleSessionlsumoodle4']
    login_request = BaseRequest("/auth/oauth2/login.php", cookies={"MoodleSessionlsumoodle4": moodle4_token})
    try: 
      redir = login_request.get({"id": "1", "wantsurl": "/", "sesskey": config["sesskey"]})
    except requests.exceptions.TooManyRedirects as e:
      logging.log(level=logging.WARNING, msg=f"Too many redirects, dumping error history: {e.response.history}")
      exit()
    
    headers = login_request.headers.copy()
    del headers['Host']
    
    logging.log(level=logging.INFO, msg=f"Login link: {redir.headers['Location']}")
    asyncio.run(self.auth_login(redir.headers['Location']))
    
    logging.log(level=logging.INFO, msg=f"Moodle 4 token: {moodle4_token}")
    logging.log(level=logging.INFO, msg=f"Authorization successful: {self.is_authorized()}")
      
  async def auth_login(self, login_url: str):
    global moodle4_token
    
    async with async_playwright() as p:
      browser = await p.chromium.launch(headless=False)
      context = await browser.new_context()
      page = await context.new_page()
      
      await context.add_cookies([{
        'name':'MoodleSessionlsumoodle4',
        'value': moodle4_token,
        'domain': "moodle.lsu.edu",
        'path': '/' 
      }])
      done = False
      
      async def handle_route(route: Route):
        nonlocal done
        global moodle4_token
        
        cookies = await context.cookies()
        
        for cookie in cookies:
          if cookie["name"] == "MoodleSessionlsumoodle4":
             if cookie["value"] != moodle4_token:
                logging.log(level=logging.INFO, msg=f"Moodle Session Key changed to {cookie["value"]}")
                moodle4_token = cookie["value"]
                
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
        
      await page.route("**/*", handle_route)
      await page.goto(login_url)
      
      while done != True and not page.is_closed():
        await asyncio.sleep(1)

  def is_authorized(self) -> bool:
    is_authorized_request = BaseRequest("/my/courses.php", cookies={"MoodleSessionlsumoodle4": moodle4_token})
    resp = is_authorized_request.get()
    if resp.status_code == 200:
      if moodle4_token != os.environ.get("moodle4_token_default"):
        with open(ENV_FP, "w") as file:
          file.write(f"moodle4_token_default={moodle4_token}")
        
      return True
    else:
      return False
  
class AuthRequest(BaseRequest):
  def __init__(self, endpoint: str, headers: dict[str, str] = {}, cookies: dict[str, str] = {}, use_post_form: bool = False):
    super().__init__(endpoint=endpoint, headers=headers, cookies=cookies, allow_redirects=True, use_post_form=use_post_form)
    self.set_tokens()
  
  def set_tokens(self) -> None:
    self.cookies["MoodleSessionlsumoodle4"] = moodle4_token
  
  def get(self, *args, **kwargs) -> requests.Response:
    self.set_tokens()
    return super().get(*args, **kwargs)
  
  def post(self, *args, **kwargs) -> requests.Response:
    self.set_tokens()
    return super().post(*args, **kwargs)
  
class ViewCourses(AuthRequest):
  def __init__(self):
    super().__init__(
      endpoint="/my/courses.php",
      headers={"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", "Sec-Fetch-Dest": "document", "Sec-Fetch-Mode": "navigate", "Sec-Fetch-User": "?1", "Upgrade-Insecure-Requests": "1"}
    )
    
  def get(self) -> requests.Response:
    return super().get()
    
  def post(self):
    raise NotImplementedError("ViewCourses does not have a post request")
  
class GetCourses(AuthRequest):
  def __init__(self):
    super().__init__(
      endpoint="/lib/ajax/service.php",
      headers={"Accept": "application/json, text/javascript, */*; q=0.01", "Origin": "https://moodle.lsu.edu", "Sec-Fetch-Dest": "empty", "Sec-Fetch-Mode": "cors", "Sec-Fetch-Site": "same-origin", "TE": "trailers", "X-Requested-With": "XMLHttpRequest"}
    )
  
  def get(self):
    raise NotImplementedError("GetCourses does not have a get request")
  
  def post(self, sesskey: str) -> requests.Response:
    params={"sesskey": sesskey, "info": "theme_snap_block_myoverview_filters"}
    data=[{"index":0,"methodname":"theme_snap_block_myoverview_filters","args":{"offset":0,"limit":0,"classification":"all","sort":"fullname","customfieldname":"","customfieldvalue":"","yeardata":"All years","progress":"Progress"}}]
    return super().post(params=params, data=data)

class GetScheduleUrl(AuthRequest):
  def __init__(self):
    super().__init__(
      endpoint="/calendar/export.php",
      use_post_form=True
    )

  def get(self):
    raise NotImplementedError("GetCourseSchedule does not have a get request")
  
  def post(self, sesskey: str) -> requests.Response:
    return super().post(data={"sesskey": sesskey, "_qf__core_calendar_export_form": "1", "events[exportevents]": "all", "period[timeperiod]": "recentupcoming", "generateurl": "Get calendar URL"})
  
  def get_calendar_url(self, sesskey: str) -> str:
    resp = self.post(sesskey)
    
    if resp.status_code == 200:
      html = resp.text
      soup = BeautifulSoup(html, "html.parser")
      url_container = soup.find(id="calendarexporturl")
      return url_container.get("value")
      
    else:
      raise ValueError(f"Get calendar url returned status code {resp.status_code}")

class GetCourseSchedule(AuthRequest):
  def __init__(self):
    super().__init__(endpoint="/blocks/wdsprefs/ical.php")

  def get(self, semester: Literal['FALL'] | Literal['SPRING'] = 'FALL', year: int = 2026) -> requests.Response:
    return super().get(params={"periods":f"LSUAM_{semester}_{year}"})
    
  def post(self):
    raise NotImplementedError("Post is not implemented on get course schedule, try get")
  
cookies = {
  "evalkit_101844_1059649":"1",
  "acceptCookies": "false",
  "EU_COOKIE_LAW_CONSENT": "false"
}

base_headers = {
  "Accept-Encoding": "gzip, deflate, br, zstd",
  "Accept-Language": "en-US,en;q=0.9",
  "Connection": "keep-alive",
  "DNT": "1",
  "Host": "moodle.lsu.edu",
  "Priority": "u=0, i",
  "Sec-GPC": "1",
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:159.0) Gecko/20100101 Firefox/159.0"
}

if __name__ == "__main__":
  logging.basicConfig(level=logging.INFO)
  
  view_endpoint = ViewCourses()
  courses_endpoint = GetCourses()
  login_endpoint = LoginRequest()
  
  if not login_endpoint.is_authorized():
    login_endpoint.get()
  
  resp = view_endpoint.get()
  logging.log(level=logging.INFO, msg=f"Status code: f{resp.status_code}")
  
  if resp.status_code != 200:
    logging.log(level=logging.ERROR, msg=f"View courses error")

  if resp.status_code == 200:  
    config = get_config(resp.text)  
    logging.log(level=logging.INFO, msg=f"M.cfg: {json.dumps(config, indent=2)}")
    sesskey = config["sesskey"]
        
    resp = courses_endpoint.post(sesskey)
    logging.log(level=logging.INFO, msg=f"\nCourses status code: {resp.status_code}")
    
    if resp.status_code != 200:
      logging.log(level=logging.ERROR, msg=f"Get courses error")
    
    else:
      if resp.json()[0].get("error", False) == True:
        logging.log(level=logging.WARNING, msg=f"Failed resp headers: {json.dumps(dict(resp.headers), indent=2)}")
        
      logging.log(level=logging.INFO, msg=f"Resp json: {json.dumps(resp.json(), indent=2)}")
      
    scheduleurl_endpoint = GetScheduleUrl()
    calender_url = scheduleurl_endpoint.get_calendar_url(sesskey)
    
    logging.log(level=logging.INFO, msg=f"All Calendar URL: {calender_url}")
    logging.log(level=logging.INFO, msg=f"All Calendar response:\n{requests.get(calender_url).text}")
    logging.log(level=logging.INFO, msg=f"Course schedule response:\n{GetCourseSchedule().get().text}")
      