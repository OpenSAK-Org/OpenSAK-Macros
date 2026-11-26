# Ask AI about an earthcache

Turns the listing of the earthcache selected in the cache list into a
ready-made prompt for an AI chat — Claude, ChatGPT, Le Chat (Mistral) or one
of your own choice — and asks it to explain the earthcache in the language
you pick. Handy for listings in a language you don't read well, and for the
geology terms that come with them.

The prompt asks the AI to help you **understand** the earthcache: explain
the geology, go through the owner's questions and tell you what to observe,
measure or photograph on site. It asks the AI **not** to write finished log
answers for you and not to guess answers that depend on what is on site,
since most earthcache owners expect the answers to be your own
observations. Please use it in that spirit.

## What it needs

- **OpenSAK 1.23.0** or newer (macro API 5; in beta until 1.23.0 is released)
- Permissions: `open` — to open the result page in your browser.
- Network: none. The macro contacts no web site itself.
- An account with the AI chat you choose, if that service needs one.

## Privacy

The macro sends nothing anywhere. It puts the prompt on your clipboard and
opens a page on your own computer. The data only leaves your computer when
you paste the prompt into the AI chat yourself (or open a link that carries
it), and from then on that service's own terms and privacy policy apply.

The prompt contains: the cache's code, name, type, difficulty and terrain,
owner, coordinates (posted and, if you have them, your corrected ones),
location, elevation, attributes, hint, waypoints, the listing text, **your own
note** for the cache and the text of the latest logs (3 by default). Remove
anything you don't want to share before you send it — the prompt is shown on
the page and can be edited in the chat before sending.

## How to use it

1. Select an earthcache in the cache list. (Another cache type works too; the
   macro asks first.)
2. Run the macro from **Macros → Macro manager…**.
3. The first time, choose the AI chat and the language the answer should be
   in. Tick **Don't ask again** to skip this question next time; hold
   **Shift** when you start the macro to change your choice later.
4. The prompt is put on the clipboard and a page opens in your browser.
   Press **Open …** to go to the AI chat.
5. For Claude, ChatGPT and Le Chat the chat usually opens with the prompt filled in.
   Otherwise — or if the listing is too long to fit in a link — paste the
   prompt with **Ctrl+V** (**Cmd+V** on a Mac).

Pictures in the listing are not part of the prompt. The page shows them, so
you can save one and drag it into the chat when it matters.

## The AI chats

| Choice | Opens | Prompt filled in |
|---|---|---|
| Claude | `https://claude.ai/new` | yes (`?q=`) |
| ChatGPT | `https://chatgpt.com/` | yes (`?q=`) |
| Le Chat (Mistral) | `https://chat.mistral.ai/chat` | yes (`?q=`) |
| Other (my own URL) | the URL you enter | only if the URL contains `{prompt}` |

With **Other**, enter the address of any AI chat. If it can take the prompt
in its address, put `{prompt}` where it goes, e.g.
`https://example.ai/chat?q={prompt}`; the macro replaces it with the
URL-encoded prompt. Without `{prompt}` the chat opens empty and you paste.

Filling in the prompt through the link depends on the AI service and may stop
working if the service changes it; pasting from the clipboard always works.

## Settings

At the top of the macro file:

- `AIS` — the AI chats in the list: name, address and whether the prompt can
  be put in the link. Add your own lines if you like.
- `LANGUAGES` — the languages offered in the form (you can also type any
  other language there).
- `MAX_LOGS` — how many of the latest logs to include (`0` for none).
- `MAX_LOG_CHARS` — longer log texts are cut.
- `MAX_LINK_CHARS` — the longest link the macro makes; a longer prompt is
  only put on the clipboard.

## Changes

- 0.2 — Le Chat (Mistral) now opens with the prompt filled in; a too-long prompt no longer leaves `{prompt}` in an "Other" URL
- 0.1 — first version
