# DEPLOYMENT - MANUAL STEPS

## ⚡ Run These Commands Now

Open **Command Prompt** or **PowerShell** and run:

### Step 1: Navigate to Project
```bash
cd C:\projects\chess_research\chess-engine
```

### Step 2: Set up Git Remote
```bash
git remote add origin https://github.com/kellykinyama12-maker/chess-engine.git
```

### Step 3: Ensure Main Branch
```bash
git branch -M main
```

### Step 4: Push Code to GitHub
```bash
git push -u origin main
```

**Note**: This may prompt for GitHub authentication. 

**Authentication Options**:
- Username + Personal Access Token (PAT)
- GitHub CLI authentication
- Browser-based login

### Step 5: Verify Push Succeeded

```bash
git remote -v
```

You should see:
```
origin  https://github.com/kellykinyama12-maker/chess-engine.git (fetch)
origin  https://github.com/kellykinyama12-maker/chess-engine.git (push)
```

### Step 6: Create Release on GitHub

```bash
gh release create v1.0 --title "ChessEngine v1.0 - Production Release" --notes-file files/GITHUB_RELEASE_NOTES.md chess_engine_v1.0.zip chess_engine_uci.exe chess_engine_test.exe
```

### Step 7: Verify Release

Visit: https://github.com/kellykinyama12-maker/chess-engine/releases

You should see v1.0 with:
- Release notes
- 3 download files
- Professional description

## ✅ Deployment Complete!

Once all steps are done:

1. ✅ Code is on GitHub
2. ✅ Release v1.0 is published
3. ✅ All files are downloadable
4. ✅ Public link is active

## 🎉 What's Next?

1. **Verify Release**: Visit the GitHub releases page
2. **Share Announcement**: Use templates from ANNOUNCEMENT_TEMPLATES.md
3. **Post to Community**: Twitter, LinkedIn, Reddit, Lichess, Chess.com

---

**Having Issues?**

- **"fatal: Cannot prompt because user interactivity has been disabled"**
  → Run commands in Command Prompt (not PowerShell ISE)

- **"remote origin already exists"**
  → Run: `git remote remove origin` then try again

- **GitHub authentication fails**
  → Create a Personal Access Token at github.com/settings/tokens
  → Use token as password instead of GitHub password

- **Files not found for release**
  → Verify you're in the right directory
  → Check files exist: `dir chess_engine*.exe`, `dir chess_engine*.zip`

---

**Timeline**: ~15-20 minutes total

Ready to deploy? Run the commands above! 🚀
