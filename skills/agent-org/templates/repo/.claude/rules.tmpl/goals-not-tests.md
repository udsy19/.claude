# Goals, not tests

Every task, at every level (overseer → supervisor → worker → sub-agent), is framed by:
1. **GOAL**: the outcome the user should experience;
2. **VISION**: what it serves;
3. **WHAT WE ARE BUILDING**: the product surface it lives in;
4. **WHAT HAS NOT WORKED**: prior attempts and why they failed.

A task is never "make test X pass". Tests can be mis-specified, and optimising against them moves
counts, not the product. Agents derive their own checks from the goal, write each check first, and
watch it fail before making it pass (`gate-independence.md` law 3). They prove results through the
real product — screenshots, drawings, short videos — on the path a user actually takes, never a
shortcut that skips the part that was broken. Work that does not reach the button the user presses
is not done.

Never weaken, delete or skip a test to get green. If a test is wrong, show why with evidence and
replace it.
