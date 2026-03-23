---
name: playwright
description: "MUST USE for any browser-related tasks. Browser automation via agent-browser CLI - verification, browsing, information gathering, web scraping, testing, screenshots, and all browser interactions. (playwright - oh-my-opencode port)"
allowed-tools:
  - Bash
---

# Browser Automation with agent-browser

## Quick Start

```bash
agent-browser open <url>        # Navigate to page
agent-browser snapshot -i       # Get interactive elements with refs
agent-browser click @e1         # Click element by ref
agent-browser fill @e2 "text"   # Fill input by ref
agent-browser close             # Close browser
```

## Core Workflow

1. Navigate: `agent-browser open <url>`
2. Snapshot: `agent-browser snapshot -i` (returns elements with refs like `@e1`, `@e2`)
3. Interact using refs from the snapshot
4. Re-snapshot after navigation or significant DOM changes

---

## Commands

### Navigation
```bash
agent-browser open <url>
agent-browser back
agent-browser forward
agent-browser reload
agent-browser close
```

### Snapshot
```bash
agent-browser snapshot            # Full accessibility tree
agent-browser snapshot -i         # Interactive elements only (recommended)
agent-browser snapshot -c         # Compact output
agent-browser snapshot -d 3       # Limit depth to 3
agent-browser snapshot -s "#main" # Scope to CSS selector
```

### Interactions (use @refs from snapshot)
```bash
agent-browser click @e1
agent-browser dblclick @e1
agent-browser fill @e2 "text"     # Clear and type
agent-browser type @e2 "text"     # Type without clearing
agent-browser press Enter
agent-browser press Control+a
agent-browser hover @e1
agent-browser check @e1
agent-browser select @e1 "value"
agent-browser scroll down 500
agent-browser drag @e1 @e2
agent-browser upload @e1 file.pdf
```

### Get Information
```bash
agent-browser get text @e1
agent-browser get html @e1
agent-browser get value @e1
agent-browser get attr @e1 href
agent-browser get title
agent-browser get url
agent-browser get count ".item"
```

### Screenshots & PDF
```bash
agent-browser screenshot
agent-browser screenshot path.png
agent-browser screenshot --full
agent-browser pdf output.pdf
```

### Wait
```bash
agent-browser wait @e1
agent-browser wait 2000
agent-browser wait --text "Success"
agent-browser wait --url "**/dashboard"
agent-browser wait --load networkidle
```

### Cookies & Storage
```bash
agent-browser cookies
agent-browser cookies set name value
agent-browser cookies clear
agent-browser storage local
agent-browser storage local set k v
```

### Network
```bash
agent-browser network route <url>
agent-browser network route <url> --abort
agent-browser network route <url> --body '{}'
agent-browser network requests
```

### Tabs
```bash
agent-browser tab
agent-browser tab new [url]
agent-browser tab 2
agent-browser tab close
```

### JavaScript
```bash
agent-browser eval "document.title"
```

---

## Global Options

| Option | Description |
|--------|-------------|
| `--session <name>` | Isolated browser session |
| `--profile <path>` | Persistent browser profile |
| `--headed` | Show browser window |
| `--cdp <port>` | Connect via Chrome DevTools Protocol |
| `--json` | Machine-readable JSON output |

---

## Example: Form Submission

```bash
agent-browser open https://example.com/form
agent-browser snapshot -i
# Shows: textbox "Email" [ref=e1], textbox "Password" [ref=e2], button "Submit" [ref=e3]

agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"
agent-browser click @e3
agent-browser wait --load networkidle
agent-browser snapshot -i  # Check result
```

## Example: Authentication with Saved State

```bash
# Login once
agent-browser open https://app.example.com/login
agent-browser fill @e1 "username"
agent-browser fill @e2 "password"
agent-browser click @e3
agent-browser wait --url "**/dashboard"
agent-browser state save auth.json

# Later sessions
agent-browser state load auth.json
agent-browser open https://app.example.com/dashboard
```

---

Install: `bun add -g agent-browser && agent-browser install`

---

## Advanced: Google OAuth Stealth Login

### 왜 일반 Playwright가 Google에 의해 차단되는가

Google은 자동화 브라우저를 여러 신호로 감지하여 로그인을 차단한다:

| 감지 신호 | 일반 Playwright 값 | 실제 Chrome 값 |
|-----------|-------------------|---------------|
| `navigator.webdriver` | `true` | `undefined` |
| `window.chrome` | `undefined` | `{ runtime: {}, ... }` |
| 타이핑 속도 | 즉시 (0ms) | 30~100ms 딜레이 |
| User-Agent | headless 문자열 포함 | 일반 Chrome UA |
| Permission API | 자동화 시그니처 | 정상 응답 |

이 중 하나라도 감지되면 "이 브라우저 또는 앱은 안전하지 않을 수 있습니다" 오류로 로그인이 차단된다.

---

### 3가지 우회 기법

#### 기법 1: `navigator.webdriver` 숨기기 (CDP via Page.addScriptToEvaluateOnNewDocument)

가장 중요한 우회 기법. 페이지 로드 전에 JS를 주입하여 webdriver 플래그를 제거한다.

```python
await page.add_init_script("""
    Object.defineProperty(navigator, 'webdriver', {
        get: () => undefined,
    });
""")
```

> ⚠️ `evaluate()`로는 부족하다 — 페이지 로드 후 실행되어 이미 감지된 이후다.
> `add_init_script()`는 모든 페이지·프레임 로드 **이전**에 주입된다.

#### 기법 2: `window.chrome` 주입

Google 로그인 페이지는 `window.chrome` 객체의 존재 여부로 실제 Chrome인지 확인한다.

```python
await page.add_init_script("""
    window.chrome = {
        runtime: {
            connect: () => {},
            sendMessage: () => {},
        },
    };
""")
```

#### 기법 3: Human-like 타이핑 (slow typing with delay)

키 입력 속도가 0ms이면 봇으로 감지된다. `type()`에 `delay` 옵션을 주어 사람처럼 타이핑한다.

```python
# fill() 대신 반드시 type() + delay 사용
await page.locator('input[type="email"]').type("user@example.com", delay=50)
await page.locator('input[type="password"]').type("password", delay=50)
```

---

### 실제 검증된 Python 스크립트 예시

아래는 `notebooklm.google.com` Google OAuth 로그인에 **실제 성공**한 패턴이다 (pseudocode 수준):

```python
import asyncio
import json
from pathlib import Path
from playwright.async_api import async_playwright

COOKIE_DIR = Path.home() / ".notebooklm-mcp-cli" / "profiles" / "default"
COOKIE_FILE = COOKIE_DIR / "cookies.json"

STEALTH_SCRIPTS = [
    # 1. webdriver 플래그 제거
    "Object.defineProperty(navigator, 'webdriver', { get: () => undefined });",
    # 2. window.chrome 주입
    "window.chrome = { runtime: { connect: ()=>{}, sendMessage: ()=>{} } };",
    # 3. permissions API 정상화
    """
    const originalQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = (parameters) =>
        parameters.name === 'notifications'
            ? Promise.resolve({ state: Notification.permission })
            : originalQuery(parameters);
    """,
    # 4. plugins 배열 fake (비어있으면 headless로 감지)
    "Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });",
]

async def google_stealth_login(email: str, password: str) -> bool:
    async with async_playwright() as p:
        browser = await p.chromium.launch(
            headless=False,  # Google은 headless 모드를 감지하므로 headed 권장
            args=["--disable-blink-features=AutomationControlled"],
        )
        context = await browser.new_context(
            user_agent=(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
        )
        page = await context.new_page()

        # 모든 stealth 스크립트를 페이지 로드 전에 주입
        for script in STEALTH_SCRIPTS:
            await page.add_init_script(script)

        # Google 로그인 시작
        await page.goto("https://accounts.google.com/signin")
        await page.wait_for_load_state("networkidle")

        # 이메일 입력 — slow typing 필수
        await page.locator('input[type="email"]').type(email, delay=50)
        await page.locator("#identifierNext").click()
        await page.wait_for_timeout(2000)  # Google 서버 응답 대기

        # 비밀번호 입력 — slow typing 필수
        await page.locator('input[type="password"]').type(password, delay=50)
        await page.locator("#passwordNext").click()
        await page.wait_for_url("**/myaccount**", timeout=15000)

        # NotebookLM으로 이동하여 쿠키 수집
        await page.goto("https://notebooklm.google.com")
        await page.wait_for_load_state("networkidle")

        # 쿠키 저장
        cookies = await context.cookies()
        COOKIE_DIR.mkdir(parents=True, exist_ok=True)
        COOKIE_FILE.write_text(json.dumps(cookies, indent=2))
        print(f"✓ 쿠키 {len(cookies)}개 저장 → {COOKIE_FILE}")

        await browser.close()
        return True

asyncio.run(google_stealth_login("shyeon0528@gmail.com", "YOUR_PASSWORD"))
```

> **실제 성공 케이스**: 위 패턴으로 `notebooklm.google.com` 로그인 성공,
> 쿠키 **27개** 저장 완료.

---

### `playwright-stealth` 라이브러리 방식 (대안)

위 수동 주입 대신 `playwright-stealth` 패키지를 사용할 수 있다:

```bash
pip install playwright-stealth
```

```python
from playwright_stealth import stealth_async

async with async_playwright() as p:
    browser = await p.chromium.launch(headless=False)
    page = await browser.new_page()
    await stealth_async(page)  # 한 줄로 모든 stealth 적용
    await page.goto("https://accounts.google.com/signin")
    # ... 이후 동일
```

> `playwright-stealth`는 내부적으로 위의 기법들을 포함한 20+ 개의 패치를 적용한다.
> 단순 사용에는 편리하나, 실패 시 수동 방식으로 개별 디버깅이 필요하다.

---

### CDP + 기존 Chrome 세션 연결 방식 (주의: 정책 차단됨)

```bash
# Chrome을 디버그 포트로 실행
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
    --remote-debugging-port=9222 --user-data-dir=/tmp/chrome-debug
```

```python
# CDP로 기존 세션에 연결
browser = await p.chromium.connect_over_cdp("http://localhost:9222")
```

> ⚠️ **실패 사례**: Google은 2024년부터 CDP 연결 자체를 감지하여
> 기업 정책(Enterprise policy)으로 차단하는 경우가 있다.
> 이미 로그인된 프로필을 재사용할 때는 동작하나, 신규 로그인에는 비추천.

---

### nlm 쿠키 저장 경로 및 검증

#### 저장 경로

```
~/.notebooklm-mcp-cli/profiles/default/cookies.json
```

#### 쿠키 파일 구조

```json
[
  {
    "name": "__Secure-1PSID",
    "value": "...",
    "domain": ".google.com",
    "path": "/",
    "expires": 1234567890,
    "httpOnly": true,
    "secure": true,
    "sameSite": "None"
  },
  ...
]
```

#### 쿠키 유효성 검증 방법

```bash
# 방법 1: nlm CLI 직접 확인 (권장)
nlm login --check
# 성공 시: ✓ Authentication valid! Notebooks found: 20

# 방법 2: 핵심 쿠키 존재 여부 확인
python3 -c "
import json
from pathlib import Path
cookies = json.loads(Path('~/.notebooklm-mcp-cli/profiles/default/cookies.json').expanduser().read_text())
names = {c['name'] for c in cookies}
required = {'__Secure-1PSID', '__Secure-3PSID', 'SID'}
missing = required - names
print('✓ OK' if not missing else f'✗ Missing: {missing}')
print(f'  총 쿠키: {len(cookies)}개')
"

# 방법 3: 만료 시각 확인
python3 -c "
import json, time
from pathlib import Path
cookies = json.loads(Path('~/.notebooklm-mcp-cli/profiles/default/cookies.json').expanduser().read_text())
expired = [c['name'] for c in cookies if c.get('expires', 0) > 0 and c['expires'] < time.time()]
print(f'만료된 쿠키: {expired if expired else \"없음\"}')
"
```

#### 쿠키 만료 시 재로그인

Google 세션 쿠키는 보통 **1년** 유효하나, 비활성 또는 보안 이벤트 시 무효화된다.
`nlm login --check` 실패 시 위 stealth 로그인 스크립트를 재실행하면 된다.
