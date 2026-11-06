# FindWordsinName

**Author:** GeePa

**Version:** 1.0

**Requires-API:** 4

**Permissions:** `write`, `open`

## Overview

**FindWordsinName** is an OpenSAK Lua macro designed to help geocachers find specific words or substrings within cache names across their database. It flags matching caches in OpenSAK and generates an interactive, sortable HTML report listing all matched geocaches along with their codes, names, owners, and log dates.

This macro is particularly useful for completing name-based challenge caches (such as finding caches with colors, animals, or specific words in their titles) or organizing geocaching data based on naming patterns.

## Technical Specifications & Header

The macro contains the following standard OpenSAK header declarations:

| Header Key | Value | Description | 
| ----- | ----- | ----- | 
| `Name` | `FindWordsinName` | Human-readable name of the macro | 
| `Author` | `GeePa` | Macro author | 
| `Version` | `1.0` | Macro version number | 
| `Requires-API` | `4` | Required OpenSAK API version (`opensak.api_version()`) | 
| `Description` | `Find words in cache name` | One-line summary of macro function | 
| `Permissions` | `write, open` | Declares database writing (flag updates) and opening HTML files in default app | 

### Required Permissions Explained

* **`write`**: Modifies data in the active OpenSAK database by setting and clearing `macro_flag` values on caches.

* **`open`**: Opens the generated HTML report file (`FindWordsinName.html`) using the system's default browser via `opensak.open()`.

## Installation & File Structure

To include this macro in a repository or manual OpenSAK installation, use the CamelCase folder and file naming structure:

```
macros/
└── FindWordsinName/
    ├── FindWordsinName.lua   ← Main macro script file
    └── README.md             ← User guide / documentation
```

* The primary folder matches the macro name (`FindWordsinName`).
* The primary `.lua` file matches the folder name (`FindWordsinName.lua`).

## How to Use

### 1. Set Your Database Filter (Optional)

* **Search Entire Database:** Clear all active filters in OpenSAK before running the macro.

* **Search Subset:** Apply your desired filter *before* running the macro. The macro respects your active filter and only searches within the visible dataset.

### 2. Run the Macro

* Press **F5** in OpenSAK to execute the macro.

* Press **F1** at any point while editing to open the OpenSAK API reference.

### 3. Configure Search Options

When launched, the dialog presents several options:

#### A. Search Mode (Stand Alone vs. Embedded)

* **Stand Alone:** Matches exact word boundaries using regex boundary tokens (`\b`).

  * *Example:* Searching for `Red` matches **"Red River"**, but skips **"Fred"** or **"Redwood"**.

* **Embedded:** Matches substrings anywhere inside the cache name.

  * *Example:* Searching for `Red` matches **"Red"**, **"Fred"**, and **"Redwood"**.

#### B. Display Title

Enter a custom title for your report (e.g., `Color Challenge Caches`). This title appears in the header of your generated HTML report along with a timestamp.

#### C. Search Keywords

Enter target words separated by commas (`,`).

* *Example:* `Red, Blue, Green`

* Spaces following commas are stripped automatically, and searches are case-insensitive (`(?i)`).

## Interface Controls

| Control / Button | Function | 
| ----- | ----- | 
| **OK** | Executes search query, updates database `macro_flag` values, and opens HTML report. | 
| **Clear** | Clears the text input field for search terms. | 
| **Cancel** | Exits macro execution with a message without altering database flags or files. | 

## Output and Results

If matches are found:

1. Matching caches in OpenSAK have their `macro_flag` updated to `true`.

2. OpenSAK applies an internal filter (`macro_flag = true`).

3. An interactive HTML table (`FindWordsinName.html`) opens in your browser featuring:

   * **Code:** Geocaching code (GC Code).

   * **Name:** Geocache name.

   * **Owner:** Cache owner name.

   * **Found:** Date logged as found.

> **Interactive Sorting:** You can click any column header in the browser view to dynamically sort results alphanumerically or by date.

If no matches are found, a popup message displays: *"Sorry, no matches found."*