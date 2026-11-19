@echo off
REM ChessEngine v1.0 - GitHub Deployment Script
REM Run this in Command Prompt or PowerShell to deploy

echo.
echo ========================================================================
echo          ChessEngine v1.0 - GitHub Deployment
echo ========================================================================
echo.

cd /d C:\projects\chess_research\chess-engine

echo Step 1: Configure Git Remote
git remote add origin https://github.com/kellykinyama12-maker/chess-engine.git

echo Step 2: Ensure on main branch
git branch -M main

echo Step 3: Push to GitHub (you may be prompted to authenticate)
echo.
echo NOTE: GitHub will prompt for authentication. Use one of:
echo   - GitHub username + personal access token
echo   - Browser-based authentication
echo   - GitHub CLI authentication
echo.
pause
git push -u origin main

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Push failed. Please verify:
    echo   1. You have internet connection
    echo   2. GitHub credentials are correct
    echo   3. Repository exists at github.com/kellykinyama12-maker/chess-engine
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================================================
echo Step 4: Create GitHub Release
echo ========================================================================
echo.

gh release create v1.0 ^
  --title "ChessEngine v1.0 - Production Release" ^
  --notes-file files/GITHUB_RELEASE_NOTES.md ^
  chess_engine_v1.0.zip chess_engine_uci.exe chess_engine_test.exe

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Release creation failed. Verify:
    echo   1. GitHub CLI is authenticated: gh auth status
    echo   2. Files exist in correct location
    echo.
    pause
    exit /b 1
)

echo.
echo ========================================================================
echo SUCCESS! Deployment Complete!
echo ========================================================================
echo.
echo Release is now live at:
echo https://github.com/kellykinyama12-maker/chess-engine/releases/tag/v1.0
echo.
echo Next steps:
echo   1. Visit the release page to verify files
echo   2. Use announcement templates from ANNOUNCEMENT_TEMPLATES.md
echo   3. Share the GitHub link with the community
echo.
pause
