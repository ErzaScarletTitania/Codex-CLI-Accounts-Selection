@ECHO off
SETLOCAL ENABLEEXTENSIONS

SET "USER_REQUESTED_LOGIN="
IF /I "%~1"=="login" SET "USER_REQUESTED_LOGIN=1"

ECHO.
ECHO Select the Codex account to use:
ECHO   1. Aleph General
ECHO   2. GTB
ECHO   3. IE - Imagined Earth
ECHO.
CHOICE /C 123 /N /M "Choose 1, 2, or 3: "
IF ERRORLEVEL 3 GOTO select_ie
IF ERRORLEVEL 2 GOTO select_gtb
GOTO select_aleph

:select_aleph
SET "ACCOUNT_LABEL=Aleph General"
SET "ACCOUNT_HOME=%USERPROFILE%\.codex"
GOTO prepare_account

:select_gtb
SET "ACCOUNT_LABEL=GTB"
SET "ACCOUNT_HOME=%USERPROFILE%\.codex-second"
GOTO prepare_account

:select_ie
SET "ACCOUNT_LABEL=IE - Imagined Earth"
SET "ACCOUNT_HOME=%USERPROFILE%\.codex-accounts\ie-imagined-earth"
GOTO prepare_account

:prepare_account
IF NOT EXIST "%ACCOUNT_HOME%" MKDIR "%ACCOUNT_HOME%"
IF EXIST "%USERPROFILE%\.codex\config.toml" IF NOT EXIST "%ACCOUNT_HOME%\config.toml" COPY /Y "%USERPROFILE%\.codex\config.toml" "%ACCOUNT_HOME%\config.toml" >NUL

SET "CODEX_HOME=%ACCOUNT_HOME%"

IF EXIST "%ACCOUNT_HOME%\auth.json" GOTO run_codex

ECHO.
ECHO No Codex login is stored yet for account '%ACCOUNT_LABEL%'.
ECHO A separate auth cache will be created in:
ECHO   %ACCOUNT_HOME%
ECHO.
ECHO Choose how to authenticate this account:
ECHO   1. Sign in with ChatGPT ^(recommended for ChatGPT Business^)
ECHO   2. Use an OpenAI API key
ECHO.
CHOICE /C 12 /N /M "Choose 1 or 2: "
IF ERRORLEVEL 2 GOTO login_with_api_key

CALL "C:\Users\lglez\AppData\Roaming\npm\codex-real.cmd" login --device-auth
IF ERRORLEVEL 1 GOTO exit_with_error
GOTO login_complete

:login_with_api_key
SET /P "OPENAI_KEY=Paste the OpenAI API key for this account: "
IF NOT DEFINED OPENAI_KEY (
    ECHO No API key was provided.
    EXIT /B 1
)
ECHO %OPENAI_KEY%| CALL "C:\Users\lglez\AppData\Roaming\npm\codex-real.cmd" login --with-api-key
SET "OPENAI_KEY="
IF ERRORLEVEL 1 GOTO exit_with_error

:login_complete
IF DEFINED USER_REQUESTED_LOGIN EXIT /B 0

:run_codex
CALL "C:\Users\lglez\AppData\Roaming\npm\codex-real.cmd" %*
SET "EXITCODE=%ERRORLEVEL%"
ENDLOCAL & EXIT /B %EXITCODE%

:exit_with_error
SET "EXITCODE=%ERRORLEVEL%"
ENDLOCAL & EXIT /B %EXITCODE%
