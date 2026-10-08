import os, sys
sys.argv = ['supervise.py', '/private/tmp/claude-501/-Users-udsy-Desktop-Design-Files-foldermemory-hierarchy/8bd330f8-0e6e-45a1-a5b9-fce8770f4483/scratchpad/sb-audit-b/s5/org/lanes/a', '1']; sys.path.insert(0, '/private/tmp/claude-501/-Users-udsy-Desktop-Design-Files-foldermemory-hierarchy/8bd330f8-0e6e-45a1-a5b9-fce8770f4483/scratchpad/sb-audit-b/s5/org')
import supervise as s
orig = s.regen_hubs
def crash(cwd, why):
    if cwd == s.REPO: os._exit(137)      # SIGKILL-equivalent right after the LAND merge, before hubs
    return orig(cwd, why)
s.regen_hubs = crash
s.main()
