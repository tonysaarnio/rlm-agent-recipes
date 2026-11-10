# Revenue Promotions — Browser Automation Appendix (optional)

Tips for driving the UI steps of [`setup-walkthrough.md`](setup-walkthrough.md) with
**playwright-cli**, from the recorded run on the meshmesh org. Nothing here is required:
the walkthrough works with any browser tool or by hand.

## General

- Open the org with an authenticated URL: `sf org open --target-org <sf_alias> --url-only`.
- **Switches:** when a click is blocked ("intercepts pointer events"), the toggle's faux
  container is in front of it. Click the element itself:
  `playwright-cli eval "el => el.click()" <ref>`.
- **Comboboxes with no clickable option ref** (the Pricing Procedure builder): type the
  value, then press **ArrowDown** and **Enter**.
- **Leftover text in a box:** click it, press Control+A and Backspace, then type again.
  Watch for a stray leading character.
- **The Pricing Procedure builder is slow.** Allow 60–120 seconds for Save and Activate.
- **Expression set pages** need the Revenue Cloud app; the Billing console shows
  "Unsupported Item".

## Tag mapping helper (walkthrough step 4)

The recorded run added the 10 Custom Tag Mappings with this helper, saved as `tools/map.sh`:

```bash
bash tools/map.sh <mappingName> <tagSearch>              # list candidate tags
bash tools/map.sh <mappingName> <tagSearch> <exactTag>   # pick, then Save & New
```

As recorded:

```bash
S(){ playwright-cli snapshot 2>&1; }
ref(){ S | grep -oP "$1 \[ref=\K[a-z0-9]+" | head -1; }
M=$(ref 'combobox "Mapping Name"'); playwright-cli click $M >/dev/null; sleep 1.5
O=$(ref "option \"$1\""); playwright-cli click $O >/dev/null; sleep 1
T=$(ref 'combobox "Context Tag"'); playwright-cli click $T >/dev/null; playwright-cli type "$2" >/dev/null; sleep 3
if [ -z "$3" ]; then S | grep -E 'option "' | sed -n '1,15p'; exit; fi
O2=$(ref "option \"$3\""); [ -z "$O2" ] && { echo "TAG NOT FOUND"; exit 1; }
playwright-cli click $O2 >/dev/null; sleep 1
B=$(ref 'button "Save & New"'); playwright-cli click $B >/dev/null; sleep 5
S | grep -oE "Tag mapping was created|rror[^\"]{0,160}" | tail -2
```

**macOS:** the stock BSD `grep` has no `-P`, so `ref()` above returns nothing there. Swap in
this definition. It gives the same refs on sample snapshot lines, but hasn't been run
against the org:

```bash
ref(){ S | sed -nE "s/.*$1 \[ref=([a-z0-9]+)\].*/\1/p" | head -1; }
```

Or install GNU grep (`brew install grep`) and call `ggrep -oP`.

If `<tagSearch>` lists no options, check `enableGlobalPromotionsForRevenueCloud` first
(walkthrough step 1b). `playwright-cli type` may also be entering the text too fast for the
box's search: type it in shorter pieces, or use a longer `sleep` before reading the
snapshot. If it is still empty, cancel the dialog, reload the page and try again.

After the loop, reload and confirm all 10 rows, then **Show more actions** → **Activate** →
**Continue**.
