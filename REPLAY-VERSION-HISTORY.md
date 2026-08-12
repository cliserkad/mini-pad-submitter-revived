# Replaying a `Version History:` block as git commits

Guide for AI agents. Mindprod source files carry their entire changelog in the file
header. This procedure converts that changelog into real git history: one commit per
version entry, authored by the original author, dated to the original release date.

This was already done for `src/com/mindprod/submitter/Submitter.java` (262 commits,
1.2 → 26.3, on branch `old-history`). Remaining candidates:

```
src/com/mindprod/http/Get.java
src/com/mindprod/http/Http.java
```

Find more with `grep -rln "Version History:" src/`.

## The source format

The block lives inside the leading `/* ... */` comment, after `Created with:`:

```java
 * Version History:
 *  2.0 2009-02-20 major refactoring. separate setParms and setPostParms. new send method. Post can have both types
 *                 of parm.
 *  2.1 2010-02-07 new methods Post.setBody Http.setRequestProperties.
 *  2.2 2010-04-05 new method getURL
```

Rules that hold across these files:

- An **entry line** is `<major>.<minor> <YYYY-MM-DD> <message>`. Version numbers are
  right-aligned, so leading whitespace varies once the major hits two digits.
- A **continuation line** has no version and no date — just indented prose belonging to
  the entry above it. Multi-line entries are common.
- Entries are in ascending chronological order. Do not sort them; trust the file.

## Procedure

### 1. Extract the block to `history.txt`

Strip the ` * ` comment prefix and write the entries to `history.txt` at the repo root,
one entry line (plus its continuations) per line. Replace the whole block in the source
header with a single line naming the version the file starts at:

```java
 * Version: 2.0
```

Commit this extraction as the base commit, authored to the *first* entry's date and
message. Every later commit then only touches that one `Version:` line, so each diff is
tiny and the log reads as a clean progression.

### 2. Replay the rest

Use the script in the appendix. It walks `history.txt`, rewrites the `Version:` line,
and commits. The commit template it follows:

```sh
git commit -m "add download3k" \
  --author="Roedy Green<roedyg@mindprod.com>" \
  --date="2007-06-02 12:00:00"
```

- `--date` sets the **author** date only. Leave the committer as the person doing the
  replay with the real wall-clock date — that keeps the reconstruction honest and
  visible in `git log --format=%cd`.
- Use `12:00:00` for the time. The changelog records dates, not times; noon avoids
  timezone-induced day slippage.
- Match the author string to whatever the file's `@author` tag says.
- Do **not** add a `Co-Authored-By: Claude` trailer. These commits are reconstructions
  attributed to the original author; a trailer would misrepresent authorship.

### 3. Commit messages

- Single-line entry → the message verbatim as the subject.
- Multi-line entry → first line as subject, blank line, remaining lines as body.
- Preserve typos and oddities verbatim (`drap thedownloadfree`, `dro hame-software`,
  a stray `, ,` in a list). This is a historical record, not a copy edit.
- **Entry with a date but no message** (`Submitter.java` had one at `1.6 2007-07-04`):
  `git commit -m ""` aborts, so fall back to `version <N>` as the subject. Flag this to
  the user afterwards rather than inventing a description.

### 4. Verify

```sh
git log --oneline | wc -l                       # base + one per entry
git log --format='%h %ad %an | %s' --date=short # dates ascend, author is right
git status --short                              # tree clean apart from history.txt
grep -n "Version:" <the source file>            # equals the final entry's version
```

Confirm the header's `@version` javadoc tag (further down the file) already matches the
final entry — it usually does, and it should not be touched by the replay.

### 5. Branch and scope

Do this on a dedicated branch (`old-history`), never on `master`. Ask before pushing —
this is a large, rewritten-looking history and the user may want to inspect it first.
Do not commit `history.txt` itself unless asked; it is scaffolding for the replay.

## Failure recovery

The script is resumable. It commits one entry at a time and exits on the first error, so
a partial run leaves valid commits behind. Pass the version to resume from as `argv[1]`
(the first version *not* yet committed) and it picks up there.

To scrap a run entirely: `git reset --hard <base commit>`.

## Appendix: the script

Written to the scratchpad, not the repo. Adjust `SRC` per target file.

```python
#!/usr/bin/env python3
"""Replay history.txt as one git commit per version entry."""
import re, subprocess, sys, pathlib

REPO = pathlib.Path("/path/to/repo")
HIST = REPO / "history.txt"
SRC = REPO / "src/com/mindprod/submitter/Submitter.java"
AUTHOR = "Roedy Green<roedyg@mindprod.com>"

entry_re = re.compile(r"^\s*(\d+\.\d+) (\d{4}-\d{2}-\d{2})\s?(.*?)\s*$")

entries = []
for raw in HIST.read_text().splitlines():
    if not raw.strip():
        continue
    m = entry_re.match(raw)
    if m:
        ver, date, msg = m.group(1), m.group(2), m.group(3)
        entries.append([ver, date, [msg] if msg else []])
    else:
        if not entries:
            sys.exit("continuation line before any entry: %r" % raw)
        entries[-1][2].append(raw.strip())

start = sys.argv[1] if len(sys.argv) > 1 else None
started = start is None

for ver, date, lines in entries:
    if not started:
        if ver == start:
            started = True
        else:
            continue
    if lines:
        message = lines[0] if len(lines) == 1 else lines[0] + "\n\n" + "\n".join(lines[1:])
    else:
        message = "version " + ver

    text = SRC.read_text()
    new, n = re.subn(r"^ \* Version: .*$", " * Version: " + ver, text, count=1, flags=re.M)
    if n != 1:
        sys.exit("could not find Version: line for " + ver)
    SRC.write_text(new)

    subprocess.run(["git", "add", str(SRC)], cwd=REPO, check=True)
    subprocess.run(
        ["git", "commit", "-m", message,
         "--author=" + AUTHOR,
         "--date=%s 12:00:00" % date],
        cwd=REPO, check=True, stdout=subprocess.DEVNULL)
    print("%s %s  %s" % (ver, date, message.splitlines()[0]))
```

Notes on why it is written this way:

- `subprocess.run` with a list, never `shell=True`. Messages contain `!`, `"`, `$`, and
  bare URLs; shell interpolation would mangle them.
- `count=1` on the substitution and a hard exit if it does not match exactly once —
  a silent no-op would produce an empty commit and desynchronize the whole run.
- The regex anchors on `^ \* Version: ` so it cannot accidentally hit the `@version`
  javadoc tag or a `VERSION_STRING` constant elsewhere in the file.
