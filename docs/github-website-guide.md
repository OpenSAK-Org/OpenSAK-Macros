# Sharing a macro with the GitHub website

This guide shows how to submit a new macro and update it later using only
the GitHub website — no git, no command line. The rules themselves are in
[CONTRIBUTING.md](../CONTRIBUTING.md).

- [Guide 1: Submitting a new macro](#guide-1-submitting-a-new-macro)
- [Guide 2: Updating your macro](#guide-2-updating-your-macro)

## Before you start

- You need a free GitHub account, and you need to be signed in.
- Have your macro ready on your computer and tested in OpenSAK.

---

## Guide 1: Submitting a new macro

### Step 1: Prepare the macro folder on your computer

1. Get the two template files from
   [`template/my-macro/`](../template/my-macro/): open each file
   (`my-macro.lua` and `README.md`) and click **Download raw file** (the
   download icon above the file). Put both in a new folder on your computer.
2. Rename the folder and the `.lua` file to your macro's name. Use lowercase
   letters, digits and hyphens only, and give both the same name:

   ```
   find-easy-traditionals/
   ├── find-easy-traditionals.lua
   └── README.md
   ```

3. Fill in the header at the top of the `.lua` file. Every line is required:

   ```lua
   -- OpenSAK Macro
   -- Name: Find easy traditionals
   -- Author: Jane Doe
   -- Version: 1.0
   -- Requires-API: 3
   -- Description: Filters for unfound traditional caches with low difficulty.
   -- Permissions: none
   ```

   - **Author:** your name or nickname — your geocaching name is fine.
   - **Permissions:** list everything the macro can do (`write`,
     `read-files`, `write-files`, `open`, `run-macros`). If it only reads
     data, write `none`.
   - **Network:** add this line only if the macro contacts web sites. Give
     plain host names such as `api.example.com`. `geocaching.com` and
     `coord.info` are not allowed.

4. Write the `README.md`: what the macro does, how to use it, and what it
   needs.
5. Don't include any personal data: no account names, home coordinates, log
   texts or databases of your own.

### Step 2: Fork the repository

1. Open <https://github.com/OpenSAK-Org/OpenSAK-Macros>.
2. Click **Fork** (top right), then **Create fork**.

You now have your own copy at `github.com/<your-name>/OpenSAK-Macros`. You
only do this once; bookmark it.

### Step 3: Upload your macro folder to your fork

1. In **your fork**, open the `macros` folder.
2. Click **Add file → Upload files**.
3. Drag your **whole macro folder** into the upload area, not just the files
   inside it. GitHub keeps the folder structure.
4. Check the file list: the paths must look like
   `macros/find-easy-traditionals/...`.
5. Under **Commit changes**:
   - Message: for example `Add find-easy-traditionals`.
   - Select **Create a new branch for this commit and start a pull request**,
     and name the branch, for example `add-find-easy-traditionals`.
   - Click **Propose changes**.

### Step 4: Open the pull request

GitHub now shows **Open a pull request**.

> ⚠️ **Check the top line before anything else.** GitHub often suggests
> your own fork as the target. It must say:
>
> **base repository: `OpenSAK-Org/OpenSAK-Macros`** · base: `main` ←
> head repository: `<your-name>/OpenSAK-Macros` · compare:
> `add-find-easy-traditionals`
>
> If the base repository is your own fork, click it and choose
> `OpenSAK-Org/OpenSAK-Macros`. A pull request into your own fork never
> reaches the maintainers.

1. Title: for example `New macro: Find easy traditionals`.
2. Description: one or two sentences on what the macro does, and anything the
   reviewer should know. Tick the boxes in the checklist.
3. Leave **Allow edits by maintainers** ticked.
4. Click **Create pull request**.

### Step 5: Watch the automatic checks

At the bottom of the pull request, the checks run (about a minute).

- ✅ **Green:** the pull request gets the label `needs review`. Wait for a
  maintainer.
- ❌ **Red:** click **Details** next to the failed check to see why. Common
  causes:
  - a header line is missing
  - a word in `Permissions` isn't on the allowed list
  - a `Network` entry isn't a plain host name
  - the Lua code has a syntax error
  - files from more than one macro folder are in the pull request

To fix something: in your fork, switch to your branch (branch dropdown at the
top left), open the file, click the ✏️ pencil, edit, and **Commit changes**
directly to that branch. The pull request updates itself and the checks run
again.

### Step 6: Review and merge

1. A maintainer reviews every new macro. Answer any questions in the pull
   request.
2. Once it's merged, the maintainer registers your GitHub account as the
   macro's owner. From then on your updates can be merged automatically (see
   Guide 2).
3. Optional: click **Delete branch** in the pull request to tidy up.

Two macros means two pull requests. Repeat Steps 3–6 with a new branch for
each.

---

## Guide 2: Updating your macro

### Step 1: Bring your fork up to date

1. Open your fork (`github.com/<your-name>/OpenSAK-Macros`), on branch `main`.
2. If GitHub says "This branch is X commits behind", click
   **Sync fork → Update branch**.

This makes sure you're editing the version that is published now.

### Step 2: Change the macro file

1. In your fork, open `macros/<your-macro>/<your-macro>.lua`.
2. Change it in one of two ways:
   - **Edit in the browser:** click ✏️ (Edit this file) and make your changes
     or paste in the new code.
   - **Replace it with your local file:** open the macro folder, click
     **Add file → Upload files**, and upload the file with exactly the same
     name. It replaces the old one.
3. Raise the `Version` in the header, for example `1.0` → `1.1`. The check
   fails if you don't.
4. If you changed what the macro does, update `Permissions` and `Network`
   too.
5. **Commit changes** → select **Create a new branch…** (for example
   `update-find-easy-traditionals-1.1`) → **Propose changes**.

### Step 3: Update the README (if needed)

1. Make sure you're on your new branch (branch dropdown).
2. Edit `README.md` with ✏️ and commit directly to the `update-…` branch.

### Step 4: Open the pull request

Same as Guide 1, Step 4 — **check the base repository**. Title, for example:
`Update find-easy-traditionals to 1.1`. Briefly say what changed.

### Step 5: Checks and merging

- **Your own macro, green checks, nothing new declared:** the pull request
  gets the label `auto-merge` and is merged automatically. ✨
- **New permission or new host declared:** a maintainer reviews it first.
- **Someone else's macro:** a maintainer reviews it. It's best to talk to the
  owner first, in an issue or in Discussions.
- **Only the README or example files changed:** a version bump isn't
  required, but bumping does no harm.

---

*Guide drafted by nagisml during the first test of this repository.*
