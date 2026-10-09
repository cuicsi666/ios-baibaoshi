#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""百宝箱联合构建辅助：把 modules/Release 下的 xcframework 注入 project.yml 依赖。"""
import os, sys

ydir = sys.argv[1] if len(sys.argv) > 1 else "."
mod_dir = os.path.join(ydir, "modules/Release")
yml = os.path.join(ydir, "project.yml")

fws = sorted([d for d in os.listdir(mod_dir) if d.endswith(".xcframework")])
block = "\n".join(
    "      - framework: modules/Release/%s\n        embed: true" % f for f in fws
)
s = open(yml, encoding="utf-8").read()
anchor = "    dependencies:\n      - target: KeyboardExt\n        embed: true"
assert anchor in s, "锚点未找到"
injected = "    dependencies:\n" + block + "\n      - target: KeyboardExt\n        embed: true"
open(yml, "w", encoding="utf-8").write(s.replace(anchor, injected))
print("注入 %d 个 xcframework 依赖" % len(fws))