#!/usr/bin/env python3
"""Copy command line tools plus every Homebrew dylib they need into an app bundle,
rewriting load paths so the app is self-contained. Usage: bundle_tools.py App.app tool..."""
import os, shutil, subprocess, sys

app = sys.argv[1]
tools = sys.argv[2:]
macos = os.path.join(app, "Contents", "MacOS")
frameworks = os.path.join(app, "Contents", "Frameworks")
os.makedirs(frameworks, exist_ok=True)

def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True).stdout.splitlines()[1:]
    return [l.strip().split(" (")[0] for l in out]

def is_brew(p): return p.startswith("/opt/homebrew") or p.startswith("/usr/local/")

copied = {}   # realpath -> bundled name
def bundle_lib(ref):
    rp = os.path.realpath(ref)
    if rp in copied: return copied[rp]
    name = os.path.basename(rp)
    dst = os.path.join(frameworks, name)
    shutil.copy2(rp, dst)
    os.chmod(dst, 0o755)
    copied[rp] = name
    fix(dst, is_lib=True)
    return name

def fix(path, is_lib):
    subprocess.run(["chmod", "u+w", path], check=True)
    if is_lib:
        subprocess.run(["install_name_tool", "-id", "@loader_path/" + os.path.basename(path), path], check=True, capture_output=True)
    for d in deps(path):
        if is_brew(d):
            name = bundle_lib(d)
            new = ("@loader_path/" if is_lib else "@executable_path/../Frameworks/") + name
            subprocess.run(["install_name_tool", "-change", d, new, path], check=True, capture_output=True)
        elif d.startswith("@rpath/"):
            name = d[len("@rpath/"):]
            new = ("@loader_path/" if is_lib else "@executable_path/../Frameworks/") + name
            subprocess.run(["install_name_tool", "-change", d, new, path], check=True, capture_output=True)
    # drop Homebrew rpaths
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True).stdout.splitlines()
    for i, l in enumerate(out):
        if l.strip() == "cmd LC_RPATH":
            rp = out[i + 2].split("path ")[1].split(" (")[0]
            if is_brew(rp): subprocess.run(["install_name_tool", "-delete_rpath", rp, path], capture_output=True)

for t in tools:
    src = os.path.realpath(shutil.which(t) or f"/opt/homebrew/bin/{t}")
    dst = os.path.join(macos, t)
    shutil.copy2(src, dst); os.chmod(dst, 0o755)
    fix(dst, is_lib=False)

# sign everything ad-hoc (install_name_tool invalidates signatures)
for f in sorted(os.listdir(frameworks)):
    subprocess.run(["codesign", "--force", "--sign", "-", os.path.join(frameworks, f)], check=True, capture_output=True)
for t in tools:
    subprocess.run(["codesign", "--force", "--sign", "-", os.path.join(macos, t)], check=True, capture_output=True)

# verify: nothing may still reference Homebrew
bad = []
for f in [os.path.join(macos, t) for t in tools] + [os.path.join(frameworks, f) for f in os.listdir(frameworks)]:
    for d in deps(f):
        if is_brew(d) or d.startswith("@rpath"): bad.append(f"{os.path.basename(f)} -> {d}")
if bad:
    print("UNRESOLVED:\n  " + "\n  ".join(bad)); sys.exit(1)
size = sum(os.path.getsize(os.path.join(frameworks, f)) for f in os.listdir(frameworks))
print(f"bundled {len(tools)} tools and {len(copied)} libraries ({size/1e6:.0f} MB)")
