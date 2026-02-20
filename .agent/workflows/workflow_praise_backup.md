---
description: Create a save point when user praises a feature
---

# Praise-Triggered Backup Workflow

This workflow is triggered when the USER explicitly praises a feature, page, or function (e.g., "ficou ótimo", "perfeito", "tá voando").

## Steps

1.  // turbo
    **Commit**: Create a specific commit with a `[SAVE POINT]` prefix.
    ```bash
    git add .
    git commit -m "[SAVE POINT] User praised: <feature_name>"
    ```
2.  // turbo
    **Tag (Optional)**: If it's a major milestone, create a lightweight tag.
    ```bash
    git tag -a "save_point_$(date +%Y%m%d_%H%M%S)" -m "User praise for <feature>"
    ```
3.  **Notify**: Inform the user that a secure restore point has been created.
