import os
import subprocess
import random
from datetime import datetime, timedelta

def run_command(command, env=None):
    try:
        result = subprocess.run(command, shell=True, check=True, text=True, capture_output=True, env=env)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {command}")
        if e.stderr:
            print(f"Error output: {e.stderr}")
        return None

def generate_random_date(start_date, end_date):
    time_delta = end_date - start_date
    random_days = random.randrange(time_delta.days)
    return start_date + timedelta(days=random_days)

def commit_with_date(file_path, commit_message, commit_date):
    env = os.environ.copy()
    env["GIT_AUTHOR_DATE"] = commit_date.isoformat()
    env["GIT_COMMITTER_DATE"] = commit_date.isoformat()
    run_command(f'git add "{file_path}"', env)
    if run_command("git status --porcelain", env):
        commit_cmd = f'git commit -m "{commit_message}"'
        try:
            subprocess.run(commit_cmd, shell=True, check=True, env=env, text=True)
            print(f"Committed {file_path} with date {commit_date}")
        except subprocess.CalledProcessError as e:
            print(f"Failed to commit {file_path}: {e}")
    else:
        print(f"No changes to commit for {file_path}, skipping.")

def main():
    repo_path = input("Enter the path to the Git repository (e.g., ./GEN-BOT): ")
    repo_url = input("Enter the Git remote URL (e.g., https://github.com/curtoz-007/GEN-BOT.git): ")
    main_file = input("Enter the main file to commit first (e.g., index.js): ")
    start_date = datetime(2025, 2, 16)
    end_date = datetime(2025, 9, 28)
    branch = "main"

    if not os.path.exists(repo_path):
        print(f"Directory {repo_path} does not exist.")
        return
    os.chdir(repo_path)

    if not os.path.exists(".git"):
        run_command("git init")
        run_command(f"git remote add origin {repo_url}")
        run_command(f"git checkout -b {branch}")

    current_branch = run_command("git rev-parse --abbrev-ref HEAD")
    if not current_branch:
        run_command(f"git checkout -b {branch}")
    elif current_branch.strip() != branch:
        run_command(f"git checkout -b {branch}")

    all_files = []
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d != ".git"]
        for file in files:
            file_path = os.path.relpath(os.path.join(root, file), ".")
            if file != "package.json1":
                all_files.append(file_path)

    if main_file in all_files:
        all_files.remove(main_file)
        all_files.insert(0, main_file)
    elif os.path.exists(main_file):
        all_files.insert(0, main_file)
    else:
        print(f"Main file {main_file} not found, proceeding with other files.")

    total_files = len(all_files)
    print(f"Total number of files to commit: {total_files}")
    print(f"Files: {', '.join(all_files)}")

    if total_files == 0:
        print("No files found to commit.")
        return

    if not run_command("git log --oneline"):
        print("Creating initial commit...")
        if os.path.exists(".gitignore"):
            run_command("git add .gitignore")
            run_command(f'git commit -m "Initial commit"')
        else:
            print("No .gitignore found, creating empty initial commit...")
            run_command("git commit --allow-empty -m 'Initial commit'")

    for i, file_path in enumerate(all_files, 1):
        if os.path.exists(file_path):
            commit_date = generate_random_date(start_date, end_date)
            commit_message = f"Add {file_path} on {commit_date.strftime('%Y-%m-%d')} ({i}/{total_files})"
            commit_with_date(file_path, commit_message, commit_date)
        else:
            print(f"File {file_path} does not exist, skipping.")

    print("Pushing to remote repository...")
    push_result = run_command(f"git push -f origin {branch}")
    if push_result:
        print("Successfully pushed to GitHub!")
    else:
        print("Failed to push to GitHub. Try the following:")
        print("- Ensure you have a valid personal access token (PAT) for HTTPS authentication.")
        print("- Run 'git push -f origin main' manually to see detailed errors.")
        print("- Verify main file and other sensitive files for secrets.")

if __name__ == "__main__":
    main()