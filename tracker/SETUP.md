# Creating the Tracker repository

Everything in this folder is the complete site. My GitHub access in this session is
scoped to `perezfiles01-droid/aveplay` and cannot create new repositories, so the
repository itself has to be created from your account. It takes about two minutes.

## 1. Create the repository

<https://github.com/new>

- **Repository name:** `Tracker`
- **Visibility:** **Private** ← the data contains internal AvePoint/ADB SharePoint
  URLs and work email addresses
- Do **not** add a README, .gitignore or licence (this folder already has them)

## 2. Push this folder into it

From a machine with git, after downloading this `tracker/` folder (or the zip I sent):

```bash
cd tracker
git init -b main
git add .
git commit -m "Tracker site: project links, documents and Drive integration"
git remote add origin https://github.com/perezfiles01-droid/Tracker.git
git push -u origin main
```

No git installed? On the new empty repository page click **uploading an existing file**
and drag the whole folder in. Keep the folder structure (`assets/`, `data/`,
`scripts/`, `.github/`).

## 3. Add the workbook

Upload `BA_Master_Tracker.xlsx` to the repository root (Add file → Upload files).
That enables the *Rebuild tracker data* workflow, so the site refreshes itself
whenever you push a newer workbook.

## 4. Turn the site on

**Settings → Pages → Build and deployment → Source: GitHub Actions.**
The included `.github/workflows/pages.yml` publishes on every push to `main`;
your URL will be `https://perezfiles01-droid.github.io/Tracker/`.

GitHub Pages on a **private** repository needs a paid plan (Pro, ~$4/month).
Free alternatives that keep it private:

- **Cloudflare Pages + Cloudflare Access** — free, connects to the GitHub repo,
  and you can restrict it to your own email address. Best option if you want it
  live and private.
- **Netlify** — free tier, site password protection is a paid add-on.
- **Local only** — `python3 -m http.server 8000` in the folder, open
  <http://localhost:8000>. Costs nothing and never leaves your machine.

Making the repository public would give you free Pages, but every internal link
and email address in `data/tracker.json` becomes publicly searchable. I would not.

## 5. Connect Google Drive

Full walkthrough in `README.md` → *Connecting Google Drive*. Short version:

1. <https://console.cloud.google.com/> → create a project.
2. **APIs & Services → Library** → enable **Google Drive API**.
3. **OAuth consent screen** → Internal if your Workspace allows, else External +
   add yourself as a test user → add scope `.../auth/drive.readonly`.
4. **Credentials → Create credentials → OAuth client ID → Web application** →
   *Authorised JavaScript origins*: `http://localhost:8000` and your live URL.
5. Copy the Client ID → open the site → **Settings** → paste → Save.
6. **Google Drive** in the sidebar → **Connect Google Drive**.

The Client ID is stored in your browser only, never in the repository.
