#!/bin/bash
# RALPH loop - run Claude Code over tasks in plan.md

MODEL="${MODEL:-claude-sonnet-4-20250514}"
DELAY="${DELAY:-2}"
PLAN="${PLAN:-plan.md}"

echo "RALPH loop starting..."
echo "Plan: $PLAN"
echo "Model: $MODEL"
echo ""

while true; do
  # Get first unchecked task from plan.md
  TASK=$(grep -m1 '^\- \[ \]' "$PLAN" 2>/dev/null | sed 's/^- \[ \] //')

  if [ -z "$TASK" ]; then
    echo ""
    echo "=== All tasks complete! ==="
    exit 0
  fi

  echo "=== Next task ==="
  echo "$TASK"
  echo ""

  PROMPT="You are working through plan.md one task at a time.

Current task: $TASK

Instructions:
1. Read AGENTS.md for project context and build instructions
2. Complete this ONE task only
3. Verify your work (run tests, check build)
4. Commit your changes with: git commit -m \"<message>\" --prompt \"$TASK\"
5. Mark the task done in plan.md by changing [ ] to [x]
6. If you learn critical operational details (e.g. how to build), update AGENTS.md

Rules:
- NEVER git push (only commit)
- ONLY work on this one task
- Exit when done so the next task can start"

  # Run Claude Code in headless mode with permissions bypassed
  claude --print --dangerously-skip-permissions --model "$MODEL" "$PROMPT"

  echo ""
  echo "=== Task iteration complete ==="
  echo ""

  sleep "$DELAY"
done
