---
layout: post
title: "Airflow DAG Parsing: How Volumes and File Changes Interact"
description: Understanding how Airflow detects DAG file changes and how it interacts with container volumes
summary: This post explores the intricacies of Airflow's DAG processing mechanism, particularly how it interacts with file changes on mounted volumes in a containerized environment, highlighting the challenges with using dynamic `.airflowignore` files.
tags: [css]
---

### 1. Introduction
I run Airflow in a Kubernetes environment, relying on a script to pull DAG definitions from a remote Git repository. My goal was to implement domain-specific DAG deployments by dynamically managing ``.airflowignore`` files. I attempted to inject these ``.airflowignore`` files directly into the Kubernetes volume where our DAGs reside. However, this seemingly straightforward approach led to unexpected challenges, uncovering some interesting details about how Airflow interacts with mounted volumes. I explored my process and lessons learned about Airflow's DAG parsing logic.

### 2. Approaches
I started by considering a few ideas:

#### 1. **Modifying `gitsync.sh` to exclude and reset ``.airflowignore``
This was quickly discarded. Without a remote version of the desired ``.airflowignore``, I couldn't reliably restore it via command line.

#### 2. Using Airflow variables to hide DAGs
I discovered that, except for ``.airflowignore``, there is no way to prevent DAG parsing. While we could add logic in the DAG's python file to skip execution based on Airflow variables, this wouldn't hide DAGs from the UI, which was not our intention.

    ```python
    import os
    from airflow import DAG
    from airflow.operators.python import PythonOperator
    from airflow.utils.dates import days_ago
    from airflow.models import Variable
    import json

    current_file_name = os.path.basename(__file__)

    ignore_dag_files_json = Variable.get("ignore_dag_files", default='[]')
    ignore_dag_files = json.loads(ignore_dag_files_json)

    if current_file_name in ignore_dag_files:
        print(f"DAG file '{current_file_name}' is in the ignore list. Skipping DAG creation.")
        exit()
        
    with DAG(
        dag_id="test_dag",
        schedule=None,
        start_date=days_ago(1),
        catchup=False,
    ) as dag:
        ...
    ```

#### 3. **Dynamically Creating ``.airflowignore`` via the API and gitsync**
This approach involved creating a temporary backup file and using `gitsync.sh` to push it to `dags/`.airflowignore``. This seemed promising and we confirmed that the files were correctly being copied, however, it didn't work as expected.

#### 4.  **Copying backed up `.airflowignore`:**
I stored ``.airflowignore`` at `/$DEPLOY_ENV/base-dags/`.airflowignore`.backup` and copy this file at `dags/`.airflowignore`` using gitsync.

```bash
while true
do
    ... 
    git fetch --depth 1 --prune origin $TARGET_BRANCH
    git reset --hard origin/$TARGET_BRANCH

    if [ -f "/home1/irteam/deploy/$DEPLOY_ENV/base-dags/`.airflowignore`.backup" ]; then
        cp "/home1/irteam/deploy/$DEPLOY_ENV/base-dags/`.airflowignore`.backup" "$GIT_DAGS_REPO_HOME/dags/`.airflowignore`"
        echo "$(date '+%Y-%m-%d %H:%M:%S') Restored dags/`.airflowignore` from `.airflowignore`.backup"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') `.airflowignore`.backup file not found, skipping dags/`.airflowignore` restoration"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') dags repo synced."

    sleep $WAIT_TIME
done
```

Although logs confirmed the `.airflowignore` was being updated, the changes weren't being reflected in Airflow. DAGs that should have been hidden were still visible and running. I confirmed there were no permission issues or that the file was modified by another user.

### 3. The Root of the Problem: Airflow DAG Parsing and Kubernetes Volume
I discovered that the issue was related to how Airflow detects file changes, and how file system changes are handled on a mounted volume. Here's a breakdown:

- Airflow's File Change Detection: Airflow's `DagFileProcessorManager` uses a polling interval to monitor for updates using `_file_stats` which stores file metadata and uses this info to populate the `_file_path_queue`.
- How `_file_stats` is Updated: `file_stats` is updated by `prepare_file_path_queue`, which checks for new files using `os.path.getmtime`. This is key to our problem.
- `os.path.getmtime` and Volume Metadata: `os.path.getmtime` retrieves modification time metadata of the file system's node.
- Git Reset and Volume Manipulation: `git reset --hard` directly manipulates the local file system of the volume node. This operation involves deleting the directory and creating new files or setting up metadata on existing files.
- Container File Creation and CoW: When you create a file inside a container on a mounted emptyDir volume, you're making changes in the container's isolated layer, which is using the Copy-on-Write (CoW) mechanism. The changes are not applied to the volume's metadata. Even though file creation affects the mtime inside the container, the actual volume node's mtime does not change.
- Airflow's Perspective: While the Airflow scheduler runs inside the container, the scheduler calls `os.path.getmtime()` against the volume's file system, not the container's. This means it cannot detect changes made through direct file creation inside the container.
- In essence, when I copy `.airflowignore` in our `gitsync.sh` , I were making changes inside the container's file system not the volume’s, so Airflow's file change detection mechanism was not triggered.

### 4. Conclusion
This experiments clearly show that `git reset` is the only method to correctly modify the `.airflowignore` file, in a way that Airflow recognizes. This means the `.airflowignore` file needs to be managed within the Git repository itself, and the mounted volume needs to have the `.airflowignore` file by git reset.
This ultimately means that a single branch strategy is not viable for our case, because each pipeline needs its specific `.airflowignore` which has to exist in Github repository. I need to manage different versions of the `.airflowignore` file for each pipeline and need to be stored in Github repository.