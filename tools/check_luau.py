"""
Structural checks for the game's Luau sources.

Run:
    python tools/check_luau.py

There is no Luau analyser on this project, and `rojo build` happily ships a
file that will not run: it packages text, it does not compile it. These are
the three failures that have actually taken the game down, each of which
left a file that still parsed:

    unbalanced braces, parens or blocks   a table left open
    constants used but never declared     a rewrite swallowed a declaration
    functions called but never defined    the same, one line further down

None of it is a parser, and it will not catch a typo inside a function. It
is the cheapest thing that catches the mistakes that have been made here
more than once.
"""
import io
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

FILES = [
    "src/ReplicatedStorage/Shared/Definitions.luau",
    "src/ServerScriptService/MachineSystem.luau",
    "src/ServerScriptService/ConveyorSystem.luau",
    "src/ServerScriptService/PlotWorkers.luau",
    "src/ServerScriptService/PlotNPCs.luau",
    "src/ServerScriptService/CharacterRig.luau",
    "src/ServerScriptService/NPCAppearance.luau",
    "src/ServerScriptService/SellSystem.luau",
    "src/ServerScriptService/InventoryManager.server.luau",
    "src/StarterPlayer/StarterPlayerScripts/ProductionItems.lua",
    "src/StarterPlayer/StarterPlayerScripts/InventoryClient.client.luau",
]

# Roblox datatypes and the short aliases this codebase pulls onto locals
KNOWN = {"R6", "MAT", "UDim", "UDim2", "CFrame", "Vector3", "Vector2", "Color3", "Enum",
         "Instance", "NumberRange", "NumberSequence", "NumberSequenceKeypoint",
         "ColorSequence", "TweenInfo", "Random", "Region3", "Ray", "BrickColor"}

GLOBALS = {
    "require", "print", "warn", "error", "assert", "pcall", "xpcall", "select",
    "type", "typeof", "tostring", "tonumber", "ipairs", "pairs", "next", "unpack",
    "setmetatable", "getmetatable", "rawget", "rawset", "rawequal", "rawlen",
    "tick", "time", "wait", "delay", "spawn", "settings", "collectgarbage",
    "Instance", "Vector3", "Vector2", "CFrame", "Color3", "UDim", "UDim2",
    "Enum", "BrickColor", "Ray", "Region3", "Random", "TweenInfo",
    "NumberRange", "NumberSequence", "NumberSequenceKeypoint",
    "ColorSequence", "ColorSequenceKeypoint", "Faces", "Axes", "PhysicalProperties",
    "game", "workspace", "script", "shared", "os", "math", "table", "string", "task",
    "utf8", "coroutine", "debug", "bit32", "buffer", "vector",
}

KEYWORDS = {"if", "then", "else", "elseif", "end", "for", "while", "do", "return",
            "local", "function", "and", "or", "not", "in", "repeat", "until", "break",
            "true", "false", "nil", "continue"}

CAPS = re.compile(r"\b([A-Z][A-Z0-9_]{2,})\b")
CALL = re.compile(r"(?<![\w.:])([a-zA-Z_][\w]*)\s*\(")


def strip(source):
    """Remove comments and string literals, character by character."""
    out = []
    i, n = 0, len(source)
    while i < n:
        c = source[i]
        if c == "-" and source[i:i + 4] == "--[[":
            end = source.find("]]", i)
            i = n if end < 0 else end + 2
        elif c == "-" and source[i:i + 2] == "--":
            end = source.find("\n", i)
            i = n if end < 0 else end
        elif c in "\"'":
            quote = c
            i += 1
            while i < n:
                if source[i] == chr(92):
                    i += 2
                    continue
                if source[i] == quote:
                    i += 1
                    break
                i += 1
        elif source[i:i + 2] == "[[":
            end = source.find("]]", i)
            i = n if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def balance(name, text):
    """Braces, parens, and function/then/do against end."""
    braces = text.count("{") - text.count("}")
    parens = text.count("(") - text.count(")")

    def count(word):
        return len(re.findall(r"\b" + word + r"\b", text))

    opens = count("function") + count("then") + count("do") - count("elseif")
    blocks = opens - count("end")

    if braces or parens or blocks:
        print(f"{name:<34} braces {braces:+d}  parens {parens:+d}  blocks {blocks:+d}")
        return False
    return True


def constants(name, text):
    """ALL_CAPS names read but never declared."""
    declared = set(re.findall(r"local\s+([A-Z][A-Z0-9_]{2,})\s*=", text))
    declared |= set(re.findall(r"local\s+function\s+([A-Z][A-Z0-9_]{2,})", text))

    missing = [m for m in sorted(set(CAPS.findall(text)) - declared - KNOWN)
               if not re.search(r"[.:]\s*" + m + r"\b", text)]

    if missing:
        print(f"{name:<34} used but never declared: {', '.join(missing)}")
        return False
    return True


def defined(name, text):
    """Functions called but never defined in the file."""
    declared = set(re.findall(r"local\s+function\s+([a-zA-Z_][\w]*)", text))
    declared |= set(re.findall(r"function\s+([a-zA-Z_][\w]*)\s*\(", text))
    for group in re.findall(r"local\s+([a-zA-Z_][\w,\s]*?)\s*=", text):
        for piece in group.split(","):
            declared.add(piece.strip())
    # A parameter is a declaration for anything called inside that function
    for params in re.findall(r"function[^(]*\(([^)]*)\)", text):
        for piece in params.split(","):
            declared.add(piece.strip())

    missing = sorted(set(CALL.findall(text)) - KEYWORDS - declared - GLOBALS)

    if missing:
        print(f"{name:<34} called but never defined: {', '.join(missing)}")
        return False
    return True


def main():
    ok = True

    for path in FILES:
        text = strip(io.open(os.path.join(ROOT, path), encoding="utf-8").read())
        name = path.split("/")[-1]
        ok = balance(name, text) and ok
        ok = constants(name, text) and ok
        ok = defined(name, text) and ok

    print("all clear" if ok else "PROBLEMS FOUND")
    return 0 if ok else 1


sys.exit(main())
