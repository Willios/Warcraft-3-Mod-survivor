#!/usr/bin/env python3
"""Keep the game's translations in step with the script.

  python tools/lang/build_catalog.py names     writes src/lang_names.lua: every name the
      script shows, and which of them Blizzard translated (their rawcode only: the
      translations themselves stay in the language archives, never in this repository).
  python tools/lang/build_catalog.py catalog   writes tools/lang/catalog.txt: every text
      the script shows that is ours to translate, numbered. It is the script's literal
      strings plus what a smoke test run really draws (needs lupa).
  python tools/lang/build_catalog.py merge     adds tools/lang/drafts/<code>.txt
      (lines "number=translation", for many texts at once) to src/lang_<code>.lua and checks them.
  python tools/lang/build_catalog.py check     lists, per language, what src/lang_<code>.lua
      misses or gets wrong (placeholders, percent signs).

A new text in the script shows in English until its language file has it: run catalog,
then check. In src/lang_<code>.lua the left side is the English text, the right side the
translation. {1} {dmg} {radius}... must stay; their order may change. \\037 is the percent sign.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "src" / "ashenvale_survivor.lua"
NAMES = ROOT / "src" / "lang_names.lua"
CATALOG = ROOT / "tools" / "lang" / "catalog.txt"
DRAFTS = ROOT / "tools" / "lang" / "drafts"
TEMPLATES = ROOT / "tools" / "lang" / "templates.txt"
PACKS = ROOT / "engine" / "build" / "lang"
LOCALES = ("frFR", "deDE", "esES", "itIT", "plPL", "ruRU")

# Our name for something Blizzard calls differently: official word it should use.
ALIASES = {"Goblin Tinker": "Ntin", "Goblin Alchemist": "Nalc", "Storm, Earth and Fire": "ANef",
           "Spirit of Vengeance": "AEsv", "Keeper": "Ekee", "Priestess": "Emoo", "Brewmaster": "Npbm"}
# Same word, other meaning: these stay ours.
NOT_OFFICIAL = {"Normal", "Heroic", "Mythic", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Alliance", "Horde",
                "Undead", "Tavern", "Night Elf", "Survivor", "Veteran", "Champion", "Scout", "Collector", "Slayer",
                "Heal", "Wave", "Buff", "Missile", "Burst", "Area", "Orbit", "Summon", "Passive", "Lightning", "Aura",
                "Scholar", "Curator", "Artisan", "Ascendant", "Hoarder", "Exterminator", "Loremaster", "Might", "Fortune",
                "Greed", "Tension", "Overtime", "Unending", "Precision", "Toughness", "Persistence", "Magnetism",
                "Wisdom", "Swiftness", "Vitality", "Vigor", "Fortitude", "Brutality", "Ferocity", "Regeneration"}
# Literal strings that are never shown.
JUNK = re.compile(r"^(Engine\w+|Blz\w+|\w+Template|\w+Backdrop|ScriptDialogButton|SurvivorUpdate\w+|ResourceBarFrame|"
                  r"[A-Z][a-z]\w{2}|[A-Z][a-z]+\d|\w+Theme|\w+Wave|WindWalk|ItemGet|ImpaleCast|attack .*|spell .*|"
                  r"Killmaim|Hvsh|Rhme|Orkn|SadMystery|TragicConfrontation|War2IntroMusic|War3XMainScreen|DarkAgents|"
                  r"HumanX1|OrcX1|UndeadX1|NightElfX1|WARCRAFT SURVIVORS|SURVIVOR .*|Twitch|Esc|\\037.*MB)$")
# Engine constants, rawcodes, icons, language names (shown as they are) and the
# script's sentence fragments, whose whole sentences are in templates.txt.
NOT_TEXT = re.compile(r"^(A[A-Z][a-z]\w|BTN.*|BTLF|CLPB|CLSB|DRAL|FORK|FRAME|BACKDROP|TEXT|SPRITE|GLUETEXTBUTTON|WS1?|"
                      r"[A-Z]+_.*|[A-Z_]+_|ESCAPE|SPACE|LEFT|RIGHT|UP|DOWN|ABCDEF.*|!@#.*|, best timed.*|\).*|"
                      r"Banish \(|Keystone \+|Upgrade \+|Installing v|.*\(up to \+|.*up to \+|Scripts/.*|NightElf\d|"
                      r"SPELL POOL - .*|English|Français|Deutsch|Español|Italiano|Polski|Русский|Mythic \+)$")
# ...but these look like rawcodes or music and are real words.
REAL = {"Back", "Buff", "Done", "Loot", "Menu", "Area", "Aura", "Bash", "Heal", "Hero", "Down", "Left", "Doom", "Epic",
        "Rare", "Next", "Wave", "Stats", "Skip", "Rank", "Haste", "Sleep", "Buy", "Off", "Max", "Up", "Right", "Burst",
        "Curse", "Mouse", "Music", "Spells", "Orbit", "Reach", "Space", "Dodge", "Might", "Greed", "Evasion", "Later",
        "Retry", "Close", "Equip", "Lich", "Demon", "Scout", "Ranger", "Armor", "Audio", "Blessing", "Thorns", "Silence",
        "Volcano", "Transmute", "Summon", "Upgrade", "Unequip", "Locked", "Selected", "Passive", "Health", "Damage",
        "Dalaran", "Zone", "Time", "Kills", "Gold", "Keys", "Item", "Save", "Exit", "Quit", "Cast", "Gear",
        "Engineer", "Keeper", "Might", "Mine", "Runs", "Wins", "Loot", "Overtime", "Survivor"}


def strip_comments(text):
    return re.sub(r"(?m)^\s*--[^\n]*$|\s--\s[^\n']*$", "", text)


def unescape(s):
    return s.replace("\\'", "'").replace('\\"', '"')


def script_names(text):
    """Every display name: name = '...', and the item tuples {'code', 'Name', 'stat'}."""
    names = {unescape(n) for n in re.findall(r"\bname = '((?:[^'\\\n]|\\.)*)'", text)}
    names |= {unescape(n) for n in re.findall(r"\{'\w{4}', '((?:[^'\\\n]|\\.)*)', '\w+'\}", text)}
    names |= {unescape(n) for n in re.findall(r"\bshort = '((?:[^'\\\n]|\\.)*)'", text)}
    names |= {unescape(n) for n in re.findall(r"\bfinal = \{[^}]*?name = '((?:[^'\\\n]|\\.)*)'", text)}
    names |= {"Alliance", "Horde", "Undead", "Night Elf", "Tavern"}
    return {n for n in names if len(n) > 2 and "{" not in n and "\\" not in n and n[0].isupper()}


def english_official():
    """{english name lower: rawcode} from the English archive's string files."""
    sys.path.insert(0, str(ROOT / "tools" / "lang"))
    import make_language_packs as packs
    archive = packs.open_local(PACKS / "War3zzLang_enUS.mpq")
    listing = packs.read_plain(archive, "(listfile)").decode("latin-1").splitlines()
    table = {}
    for name in listing:
        if not re.search(r"Strings\.txt$", name, re.I) or not name.lower().startswith("units\\"):
            continue
        section = None
        for line in packs.read_plain(archive, name).decode("utf-8", "replace").splitlines():
            line = line.strip()
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1]
            elif section and line.lower().startswith("name="):
                value = re.sub(r"\|[nN]", " ", line[5:]).strip().strip('"')
                table.setdefault(value.lower(), section)
    return table


def lua_string(s):
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n") + "'"


def write_names():
    text = SRC.read_text(encoding="utf-8")
    names = script_names(text)
    official_by_name = english_official()
    # A spell's or item's own rawcode when its English name is the official one.
    own = {}
    for name, code in re.findall(r"spell\('\w+', \{name = '((?:[^'\\\n]|\\.)*)', code = '(\w{4})'", text):
        own[unescape(name)] = code
    official, ours = {}, []
    for name in sorted(names):
        code = ALIASES.get(name)
        if not code and name not in NOT_OFFICIAL:
            code = official_by_name.get(name.lower())
        if code:
            official[name] = code
        else:
            ours.append(name)
    lines = ["-- Generated by tools/lang/build_catalog.py names. Do not edit.",
             "-- Every name the script shows, and the rawcode of those Blizzard translated",
             "-- (the language archive holds the translation).",
             "Lang.official = {"]
    for name in sorted(official):
        lines.append("    [%s] = '%s'," % (lua_string(name), official[name]))
    lines.append("}")
    lines.append("Lang.names = {")
    for name in sorted(names, key=lambda n: (-len(n), n)):
        lines.append("    %s," % lua_string(name))
    lines.append("}")
    NAMES.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("%d names: %d official, %d ours" % (len(names), len(official), len(ours)))
    print("ours:", ", ".join(ours))
    return official


def official_names():
    text = NAMES.read_text(encoding="utf-8")
    block = text.split("Lang.official = {")[1].split("\n}")[0]
    return {unescape(n) for n in re.findall(r"\['((?:[^'\\]|\\.)*)'\] =", block)}


def literal_strings(text):
    code = strip_comments(text)
    found = set()
    for s in re.findall(r"'((?:[^'\\\n]|\\.)*)'", code):
        if "\\\\" in s or re.search(r"\.(mdx?|blp|tga|wav|mp3|slk|pld|lua|txt)\b", s, re.I):
            continue
        s = unescape(s)
        if not re.search(r"[A-Za-z]{2}", s) or s != s.strip() or "\\n" in s:
            continue
        if JUNK.match(s) and s not in REAL:
            continue
        if " " not in s and not re.match(r"^[A-Z]", s):
            continue
        if re.match(r"^[a-z]", s) and not re.search(r"[.!]$", s):
            continue
        found.add(s)
    return found


def runtime_keys():
    """Pieces a smoke test run sends to the screen, as the script would look them up."""
    import lupa.lua53 as lua
    here = ROOT / "tools" / "smoketest"
    rt = lua.LuaRuntime(unpack_returned_tuples=True)
    loader = rt.eval("function(s, n) local f, e = load(s, n) if not f then error(e) end return f end")

    def run(path):
        return loader(path.read_text(encoding="utf-8"), "@" + path.name)()

    keys = set()

    def capture(*args):
        line = " ".join(str(a) for a in args)
        if line.startswith("LANGMISS "):
            keys.add(line[9:].replace("%", "\\037"))

    run(here / "mock.lua")
    rt.globals().print = capture
    rt.execute("""
        Engine_collect = true
        function EngineCvar(name)
            if name == 'fs_language' then return 'xxXX' end
            if name == 'survivor_lang_debug' then return '1' end
            return ''
        end
        function EngineLoadScript(path) return false end
    """)
    source = SRC.read_text(encoding="utf-8")
    names = NAMES.read_text(encoding="utf-8").split("Lang.names = {")[1].split("\n}")[0]
    marker = re.search(r"do\r?\n    local load = rawget\(_G, 'EngineLoadScript'\)", source)
    source = source[:marker.start()] + "Lang.names = {" + names + "\n}\n" + source[marker.start():]
    loader(source, "@ashenvale_survivor.lua")()
    try:
        run(here / "drive.lua")
    except Exception as error:  # A drive failure still leaves what it reached.
        print("drive stopped:", error)
    return keys


def write_catalog():
    text = SRC.read_text(encoding="utf-8")
    official = official_names()
    keys = literal_strings(text)
    templates = set()
    if TEMPLATES.is_file():
        templates = {l for l in TEMPLATES.read_text(encoding="utf-8").splitlines() if l.strip() and not l.startswith("#")}
    keys |= templates
    # What a smoke run draws is only printed, for review: a description's colour codes
    # split it there, while the game translates it whole, before they are added.
    if "--seen" in sys.argv:
        for k in sorted(runtime_keys() - keys - official):
            print("   run:", k)
    keys -= official
    keys = {re.sub(r"  +", " ", k).strip() for k in keys}
    keys = {k for k in keys if not NOT_TEXT.match(k)}
    # A text keeps its number: new ones go at the end, gone ones leave a gap.
    numbered = read_catalog() if CATALOG.is_file() else {}
    numbered = {n: k for n, k in numbered.items() if k in keys}
    known = set(numbered.values())
    next_number = max(numbered, default=0) + 1
    for key in sorted(keys - known):
        numbered[next_number] = key
        next_number += 1
    with open(CATALOG, "w", encoding="utf-8", newline="\n") as out:
        for number in sorted(numbered):
            out.write("%d\t%s\n" % (number, numbered[number]))
    words = sum(len(k.split()) for k in numbered.values())
    print("%d texts, %d words -> %s" % (len(numbered), words, CATALOG))


def read_catalog():
    entries = {}
    for line in CATALOG.read_text(encoding="utf-8").splitlines():
        number, _, key = line.partition("\t")
        entries[int(number)] = key
    return entries


PLACEHOLDER = re.compile(r"\{\w+\}")


def problems(key, value):
    found = []
    if sorted(set(PLACEHOLDER.findall(key))) != sorted(set(PLACEHOLDER.findall(value))):
        found.append("placeholders differ")
    if ("\\037" in key) != ("\\037" in value):
        found.append("percent sign differs")
    if "%" in value:
        found.append("raw percent sign, write \\037")
    if not value.strip():
        found.append("empty")
    return found


def merge():
    catalog = read_catalog()
    for draft in sorted(DRAFTS.glob("*.txt")):
        code = draft.stem
        target = ROOT / "src" / ("lang_%s.lua" % code)
        # A draft adds to the language file: corrections made there stay.
        strings = read_language(target) if target.is_file() else {}
        for line in draft.read_text(encoding="utf-8").splitlines():
            if not line.strip() or line.startswith("#"):
                continue
            number, _, value = line.partition("=")
            key = catalog.get(int(number))
            if key is None:
                print(code, "unknown number", number)
                continue
            for problem in problems(key, value):
                print("%s %s: %s\n    %s\n    %s" % (code, number, problem, key, value))
            strings[key] = value.strip()
        lines = ["-- Translation of Warcraft Survivors: English text on the left, translation on the right.",
                 "-- Spell, hero, unit and item names that Blizzard translated are not here: they come",
                 "-- from the game's own data. {1} {dmg} {radius}... must stay (their order may change),",
                 "-- \\037 is the percent sign. See tools/lang/build_catalog.py.",
                 "Lang.add({"]
        for key in sorted(strings):
            lines.append("    [%s] = %s," % (lua_quoted(key), lua_quoted(strings[key])))
        lines.append("})")
        target.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
        print("%s: %d of %d" % (target.name, len(strings), len(catalog)))


def lua_quoted(s):
    # Catalog texts hold \037 as written in the script, so backslashes stay as they are.
    return "'" + s.replace("'", "\\'") + "'"


def read_language(path):
    text = path.read_text(encoding="utf-8")
    return {unescape(k): unescape(v) for k, v in re.findall(r"\['((?:[^'\\\n]|\\.)*)'\] = '((?:[^'\\\n]|\\.)*)',", text)}


def check():
    catalog = read_catalog()
    bad = 0
    for code in LOCALES:
        path = ROOT / "src" / ("lang_%s.lua" % code)
        if not path.is_file():
            print(code, "has no file")
            bad += 1
            continue
        strings = read_language(path)
        missing = [k for k in catalog.values() if k not in strings]
        extra = [k for k in strings if k not in catalog.values()]
        print("%s: %d translated, %d missing, %d no longer used" % (code, len(strings), len(missing), len(extra)))
        for k in missing[:12]:
            print("   missing:", k)
        for key, value in strings.items():
            for problem in problems(key, value):
                print("   %s: %s" % (problem, key))
                bad += 1
    return bad


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "names":
        write_names()
    elif command == "catalog":
        write_catalog()
    elif command == "merge":
        merge()
    elif command == "check":
        sys.exit(1 if check() else 0)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
